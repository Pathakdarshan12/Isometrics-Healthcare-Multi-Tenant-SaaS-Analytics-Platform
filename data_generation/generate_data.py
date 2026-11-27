"""
IsoMetrics synthetic healthcare data engine.

Generates all 21 raw tables with realistic distributions and tenant-consistent
relationships, at multi-million-row scale:

- Vectorized: numeric, categorical and timestamp fields are drawn as NumPy
  arrays; variable child-record counts (vitals per encounter, orders per
  encounter, administrations per order) are expanded with np.repeat instead of
  Python loops.
- Streaming: patients and encounters are produced in batches. Each batch's
  dependent tables are generated and written immediately (PyArrow
  ParquetWriter / CSV append) and then released, so peak memory is bounded by
  --batch-size, not by the size of the dataset.
- Reproducible: one seed drives a single numpy Generator (plus the stdlib and
  Faker RNGs used by the smaller tables). The same arguments produce the same
  data.
- Tenant-consistent: every patient, provider and facility reference is drawn
  from the referencing row's own hospital through precomputed lookups.
- Schema-exact: output is conformed to the raw DDL (data_generation/schema.py).

Usage (from the repo root):
    python data_generation/generate_data.py                              # 100 hospitals, 30 days
    python data_generation/generate_data.py --target-encounters 3000000  # ~235 days at 100 hospitals
    python data_generation/generate_data.py --hospitals 50 --days 7 --format both

Output: data_generation/parquet/<table>.parquet (and/or data_generation/2025/<table>.csv),
plus generation_report.json with per-table throughput, write time and peak RAM.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import sys
import time
from collections import defaultdict
from datetime import timedelta

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.compute as pc
from faker import Faker

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from clinical_codes_library import CHRONIC_DIAGNOSES, COMMON_ALLERGENS, LAB_TESTS, MEDICATIONS  # noqa: E402
from medical_codes_library import (  # noqa: E402
    ADMISSION_TYPES, CPT_CODES, DENIAL_REASONS, DISCHARGE_DISPOSITIONS, HOSPITAL_DISTRIBUTION, ICD10_CODES,
    PAYERS, SPECIALTIES, US_REGIONS,
)
from schema import TableWriter  # noqa: E402

DEFAULT_SEED = 42
DEFAULT_HOSPITALS = 100
DEFAULT_BATCH_SIZE = 500_000   # max rows per batch across a parent table and all its children
# Initial rows-per-parent estimates (refined from each written batch, see generate_dataset):
# an encounter fans out to ~30 rows (vitals, orders, results, med administrations, ...),
# a patient to ~5 (allergies, problems, coverage, SDOH).
INITIAL_ROWS_PER_ENCOUNTER = 30.0
INITIAL_ROWS_PER_PATIENT = 5.0

ENCOUNTER_TYPES = np.array(['Inpatient', 'Outpatient', 'Emergency', 'Observation'], dtype=object)
ENCOUNTER_TYPE_WEIGHTS = np.array([0.20, 0.50, 0.25, 0.05])
FACILITY_TARGETS = {
    'Emergency': ['Emergency Department'],
    'Inpatient': ['Medical-Surgical Unit', 'Intensive Care Unit'],
    'Outpatient': ['Outpatient Clinic'],
    'Observation': ['Medical-Surgical Unit', 'Outpatient Clinic'],
}
ESSENTIAL_FACILITIES = ['Emergency Department', 'Medical-Surgical Unit', 'Intensive Care Unit',
                        'Operating Room', 'Outpatient Clinic']
FACILITY_CAPACITY_RATIO = {'Emergency Department': 0.05, 'Intensive Care Unit': 0.10,
                           'Medical-Surgical Unit': 0.50, 'Operating Room': 0.03, 'Outpatient Clinic': 0.05}
DEPARTMENTS = {'Emergency Medicine': 'Emergency Department', 'Internal Medicine': 'Medicine',
               'Family Medicine': 'Primary Care', 'Cardiology': 'Cardiology', 'General Surgery': 'Surgery',
               'Orthopedic Surgery': 'Surgery', 'Obstetrics': "Women's Health"}
DRUG_ALLERGENS = {'Penicillin', 'Sulfa', 'Morphine'}

SECOND = np.timedelta64(1, 's')
MINUTE = np.timedelta64(60, 's')
HOUR = np.timedelta64(3600, 's')
DAY = np.timedelta64(86400, 's')


# ---------------------------------------------------------------------------
# Small vectorized helpers
# ---------------------------------------------------------------------------

def scaled_distribution(total_hospitals: int) -> dict:
    """HOSPITAL_DISTRIBUTION with counts scaled to `total_hospitals`, keeping the type mix."""
    base_total = sum(cfg['count'] for cfg in HOSPITAL_DISTRIBUTION.values())
    types = list(HOSPITAL_DISTRIBUTION)
    raw = [HOSPITAL_DISTRIBUTION[t]['count'] * total_hospitals / base_total for t in types]
    counts = [int(x) for x in raw]
    for i in sorted(range(len(types)), key=lambda i: raw[i] - counts[i], reverse=True)[:total_hospitals - sum(counts)]:
        counts[i] += 1  # largest remainders
    return {t: {**HOSPITAL_DISTRIBUTION[t], 'count': c} for t, c in zip(types, counts)}


def expected_daily_encounters(distribution: dict) -> float:
    return sum(cfg['count'] * sum(cfg['daily_encounters']) / 2 for cfg in distribution.values())


def make_ids(prefix: str, start: int, n: int, width: int) -> np.ndarray:
    """'<prefix><zero-padded n>' IDs, built in Arrow compute (~2x a Python f-string loop)."""
    if n == 0:
        return np.array([], dtype=object)
    numbers = pc.utf8_lpad(pa.array(np.arange(start, start + n)).cast(pa.string()), width, '0')
    return pc.binary_join_element_wise(prefix, numbers, '').to_numpy(zero_copy_only=False)


_HASH_SALTS = {'SSN': 0x5353_4E00, 'PHONE': 0x5048_4F4E, 'EMAIL': 0x454D_4149}


def short_hash(kind: str, numbers: np.ndarray) -> np.ndarray:
    """Deterministic 16-hex-character token per (kind, number), vectorized.

    Stand-in for hashing a synthetic identifier (the values are synthetic, so
    no cryptographic property is needed): SplitMix64 over number + per-kind
    salt, hex-encoded in one pass. ~4x faster than per-row SHA-256 and the same
    format (16 lowercase hex chars) as before.
    """
    with np.errstate(over='ignore'):
        z = (np.asarray(numbers, dtype=np.uint64) + np.uint64(_HASH_SALTS[kind])) * np.uint64(0x9E3779B97F4A7C15)
        z = (z ^ (z >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        z = (z ^ (z >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        z ^= z >> np.uint64(31)
    hex_bytes = z.astype('>u8').tobytes().hex().encode()
    return np.frombuffer(hex_bytes, dtype='S16').astype('U16').astype(object)


def concat_str(*parts) -> np.ndarray:
    """Element-wise string concatenation of arrays and scalars."""
    out = pd.Series([''] * len(next(p for p in parts if not isinstance(p, str))), dtype=object)
    for p in parts:
        out = out + (p if isinstance(p, str) else pd.Series(p, dtype=object).astype(str).to_numpy())
    return out.to_numpy(dtype=object)


def nullable(values: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """values where mask, else None (object array)."""
    out = np.full(len(values), None, dtype=object)
    out[mask] = np.asarray(values, dtype=object)[mask]
    return out


def nat_where(values: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """datetime values where mask, else NaT."""
    out = np.full(len(values), np.datetime64('NaT'), dtype='datetime64[s]')
    out[mask] = values[mask]
    return out


def expand(counts: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """For per-parent child counts, return (parent index, position within parent) per child."""
    counts = np.asarray(counts, dtype=np.int64)
    parent = np.repeat(np.arange(len(counts)), counts)
    starts = np.repeat(np.cumsum(counts) - counts, counts)
    return parent, np.arange(len(parent)) - starts


class GroupSampler:
    """Uniformly sample a member of a group per row, e.g. a provider of the row's hospital."""

    def __init__(self, groups: dict):
        keys = [k for k, members in groups.items() if len(members)]
        self.index = {k: i for i, k in enumerate(keys)}
        self.sizes = np.array([len(groups[k]) for k in keys], dtype=np.int64)
        self.offsets = np.concatenate([[0], np.cumsum(self.sizes)[:-1]]).astype(np.int64)
        self.members = np.array([m for k in keys for m in groups[k]], dtype=object)

    def _group_index(self, keys) -> np.ndarray:
        # factorize: map only the (few) distinct keys, not every row
        codes, uniques = pd.factorize(np.asarray(keys, dtype=object))
        lookup = np.array([self.index.get(k, -1) for k in uniques], dtype=np.int64)
        if (lookup < 0).any():
            raise KeyError(f'no members for group(s): {[k for k, i in zip(uniques, lookup) if i < 0][:5]}')
        return lookup[codes]

    def sample(self, keys, rng: np.random.Generator) -> np.ndarray:
        gi = self._group_index(keys)
        picks = self.offsets[gi] + (rng.random(len(gi)) * self.sizes[gi]).astype(np.int64)
        return self.members[picks]

    def sample_distinct(self, keys, k: int, rng: np.random.Generator) -> np.ndarray:
        """k distinct members per row (fewer if the group is smaller), joined with ','."""
        gi = self._group_index(keys)
        size = self.sizes[gi]
        first = (rng.random(len(gi)) * size).astype(np.int64)
        picks = [self.members[self.offsets[gi] + (first + j) % size] for j in range(k)]
        joined = picks[0].astype(object)
        for j in range(1, k):
            joined = np.where(size > j, joined + ',' + picks[j], joined)
        return joined


# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------

class HealthcareDataGenerator:
    """Synthetic data for all raw tables. Methods return DataFrames for one batch."""

    # Diagnosis-driven CMS measure cohorts:
    # code -> (measure_code, measure_name, category, timing field, target minutes)
    QUALITY_MEASURE_COHORTS = {
        'A41.9': ('SEP-1', 'Severe Sepsis and Septic Shock Management Bundle', 'SEPSIS',
                  'door_to_antibiotic_minutes', 60),
        'I21.9': ('AMI-8a', 'Primary PCI Received Within 90 Minutes of Arrival', 'AMI',
                  'door_to_balloon_minutes', 90),
        'I63.9': ('STK-4', 'Thrombolytic Therapy Within 60 Minutes of Arrival', 'STROKE',
                  'door_to_needle_minutes', 60),
        'I50.9': ('HF-2', 'Evaluation of LVS Function', 'HF', None, None),
        'J18.9': ('PN-6', 'Initial Antibiotic Selection for CAP', 'PNEUMONIA', None, None),
    }

    CARE_PLAN_TEMPLATES = {
        'Cardiovascular': ('Cardiac risk management', 'Maintain BP < 130/80 and LDL at goal',
                           'Medication titration, low-sodium diet education, cardiology follow-up'),
        'Endocrine': ('Glycemic control', 'HbA1c < 7.0% within 90 days',
                      'Insulin/oral agent adjustment, diabetes self-management education'),
        'Respiratory': ('Respiratory function optimization', 'No exacerbation-related ED visits in 90 days',
                        'Inhaler technique teaching, pulmonary rehab referral, smoking cessation'),
        'Renal': ('CKD progression management', 'Stable eGFR over 6 months',
                  'Nephrology follow-up, renal diet, nephrotoxic medication review'),
        'Infectious': ('Infection resolution', 'Afebrile with normal WBC before discharge',
                       'Culture-guided antibiotics, sepsis bundle compliance, line care'),
    }
    DEFAULT_CARE_PLAN = ('General recovery', 'Return to baseline functional status',
                         'Early mobilization, fall precautions, discharge planning')

    REFERRAL_SPECIALTIES = {
        'Cardiovascular': 'Cardiology', 'Endocrine': 'Endocrinology', 'Respiratory': 'Pulmonology',
        'Renal': 'Nephrology', 'Neurological': 'Neurology', 'Infectious': 'Infectious Disease',
        'Oncology': 'Oncology', 'Musculoskeletal': 'Orthopedics', 'Mental Health': 'Psychiatry',
    }

    def __init__(self, start_date='2025-01-01', end_date='2025-01-31', seed: int = DEFAULT_SEED,
                 distribution: dict | None = None, verbose: bool = True, id_namespace: str | None = None):
        self.start_date = pd.Timestamp(start_date)
        self.end_date = pd.Timestamp(end_date)
        self.days = (self.end_date.normalize() - self.start_date.normalize()).days + 1
        # "today" for fields relative to the present (onset dates, evaluations): the end
        # of the generated period, so output doesn't depend on the wall clock.
        self.as_of = self.end_date
        self.distribution = distribution or HOSPITAL_DISTRIBUTION
        self.verbose = verbose

        self.seed = seed
        self.rng = np.random.default_rng(seed)
        random.seed(seed)
        np.random.seed(seed)
        Faker.seed(seed)
        self.fake = Faker()
        self.fake.seed_instance(seed)
        self._pools: dict[str, np.ndarray] = {}

        self.id_namespace = id_namespace
        self.rows_per_encounter = INITIAL_ROWS_PER_ENCOUNTER
        self.rows_per_patient = INITIAL_ROWS_PER_PATIENT
        self._counters: dict[str, int] = defaultdict(int)
        self.hospital_patients: dict[str, list] = defaultdict(list)
        self.hospital_providers: dict[str, list] = defaultdict(list)
        self.hospital_facilities: dict[str, list] = defaultdict(list)
        # last inpatient discharge per patient (epoch seconds) for O(1) readmission flags
        self.last_inpatient_discharge: dict[str, int] = {}
        self._samplers: dict[str, GroupSampler] = {}

    # -- infrastructure ------------------------------------------------------

    def log(self, msg: str) -> None:
        if self.verbose:
            print(msg, flush=True)

    def _next_ids(self, prefix: str, n: int, width: int = 12) -> np.ndarray:
        """Sequential IDs per prefix. With id_namespace set (incremental batches), IDs are
        '<prefix><namespace>_<n:07d>', so separately generated batches never collide."""
        start = self._counters[prefix] + 1
        self._counters[prefix] += n
        if self.id_namespace:
            return make_ids(f'{prefix}{self.id_namespace}_', start, n, 7)
        return make_ids(prefix, start, n, width)

    def _pool(self, name: str, size: int = 2000) -> np.ndarray:
        """Faker values are expensive; draw a pool once and sample from it."""
        if name not in self._pools:
            make = {
                'first_male': self.fake.first_name_male, 'first_female': self.fake.first_name_female,
                'first': self.fake.first_name, 'last': self.fake.last_name, 'zip': self.fake.zipcode,
                'city': self.fake.city, 'state': self.fake.state_abbr, 'company': self.fake.company,
            }[name]
            self._pools[name] = np.array([make() for _ in range(size)], dtype=object)
        return self._pools[name]

    def _pick(self, values, n: int, p=None) -> np.ndarray:
        values = np.asarray(values, dtype=object)
        return values[self.rng.choice(len(values), size=n, p=p)]

    def _sampler(self, name: str) -> GroupSampler:
        if name not in self._samplers:
            groups = {'patients': self.hospital_patients, 'providers': self.hospital_providers}[name]
            self._samplers[name] = GroupSampler(groups)
        return self._samplers[name]

    def load_reference(self, patients: pd.DataFrame, providers: pd.DataFrame, facilities: pd.DataFrame) -> None:
        """Use existing master data (e.g. read from Snowflake) instead of generating it."""
        self.hospital_patients = defaultdict(list, patients.groupby('hospital_id')['patient_id'].apply(list).to_dict())
        self.hospital_providers = defaultdict(list, providers.groupby('hospital_id')['provider_id'].apply(list).to_dict())
        self.hospital_facilities = defaultdict(
            list, facilities.groupby('hospital_id')['facility_id'].apply(list).to_dict())
        self.index_facilities(facilities)

    def index_facilities(self, facilities: pd.DataFrame) -> None:
        """Precompute (hospital, encounter type) -> eligible facilities, replacing per-row filtering."""
        by_hospital_type = defaultdict(list)
        for row in facilities.itertuples(index=False):
            by_hospital_type[(row.hospital_id, row.facility_type)].append(row.facility_id)
        groups = {}
        for hospital_id, all_facilities in self.hospital_facilities.items():
            for enc_type, targets in FACILITY_TARGETS.items():
                eligible = [f for t in targets for f in by_hospital_type.get((hospital_id, t), [])]
                groups[f'{hospital_id}|{enc_type}'] = eligible or list(all_facilities)
        self._samplers['facilities'] = GroupSampler(groups)
        self._samplers.pop('patients', None)
        self._samplers.pop('providers', None)

    # -- master data ------------------------------------------------------------

    @staticmethod
    def get_region(state: str) -> str:
        for region, states in US_REGIONS.items():
            if state in states:
                return region
        return 'Other'

    def generate_hospitals(self) -> pd.DataFrame:
        rows, n = [], 0
        cities, states = self._pool('city', 500), self._pool('state', 500)
        for h_type, cfg in self.distribution.items():
            for _ in range(cfg['count']):
                n += 1
                city, state = random.choice(cities), random.choice(states)
                emr = random.choice(cfg['emr_system']) if isinstance(cfg['emr_system'], list) else cfg['emr_system']
                rows.append({
                    'hospital_id': f'HOSP_{n:04d}',
                    'hospital_name': f"{city} {h_type.replace('_', ' ').title()}",
                    'hospital_type': h_type,
                    'bed_count': random.randint(*cfg['bed_count']),
                    'city': city, 'state': state, 'region': self.get_region(state),
                    'emr_system': emr, 'contract_tier': cfg['contract_tier'],
                    'contract_start_date': (self.start_date - timedelta(days=random.randint(365, 730))).date(),
                    'is_active': True,
                    'teaching_hospital': h_type == 'academic_medical_center',
                })
        return pd.DataFrame(rows)

    def generate_providers(self, hospitals: pd.DataFrame) -> pd.DataFrame:
        frames = []
        for h in hospitals.itertuples(index=False):
            cfg = self.distribution[h.hospital_type]
            n = int(self.rng.integers(cfg['providers'][0], cfg['providers'][1] + 1))
            ids = self._next_ids('PROV_', n, 8)
            specialty = self._pick(SPECIALTIES[:cfg['specialties']], n)
            contract_start = np.datetime64(pd.Timestamp(h.contract_start_date), 'D')
            frames.append(pd.DataFrame({
                'provider_id': ids,
                'hospital_id': h.hospital_id,
                'npi': self.rng.integers(1_000_000_000, 10_000_000_000, n).astype(str),
                'provider_first_name': self._pick(self._pool('first'), n),
                'provider_last_name': self._pick(self._pool('last'), n),
                'specialty': specialty,
                'department': pd.Series(specialty).map(DEPARTMENTS).fillna('Medicine').to_numpy(),
                'provider_type': self._pick(['MD', 'DO', 'NP', 'PA'], n),
                'hire_date': contract_start + self.rng.integers(-1000, 1, n).astype('timedelta64[D]'),
                'is_active': True,
                'accepts_new_patients': self.rng.random(n) < 0.5,
            }))
            self.hospital_providers[h.hospital_id].extend(ids)
        self._samplers.pop('providers', None)
        return pd.concat(frames, ignore_index=True)

    def generate_facilities(self, hospitals: pd.DataFrame) -> pd.DataFrame:
        rows, n = [], 0
        for h in hospitals.itertuples(index=False):
            for facility_type in ESSENTIAL_FACILITIES:
                n += 1
                fac_id = f'FAC_{n:08d}'
                rows.append({
                    'facility_id': fac_id, 'hospital_id': h.hospital_id,
                    'facility_name': f'{h.hospital_name} - {facility_type}', 'facility_type': facility_type,
                    'bed_capacity': max(int(h.bed_count * FACILITY_CAPACITY_RATIO.get(facility_type, 0.10)), 5),
                    'is_active': True, 'opened_date': h.contract_start_date,
                })
                self.hospital_facilities[h.hospital_id].append(fac_id)
        facilities = pd.DataFrame(rows)
        self.index_facilities(facilities)
        return facilities

    def generate_reference_tables(self) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
        diagnoses = pd.DataFrame([{
            'diagnosis_code': code, 'diagnosis_description': d['description'], 'category': d['category'],
            'severity_level': d['severity'], 'is_chronic': d['severity'] in ('High', 'Critical'),
        } for code, d in ICD10_CODES.items()])
        procedures = pd.DataFrame([{
            'procedure_code': code, 'procedure_description': d['description'], 'category': d['category'],
            'typical_charge_min': d['typical_charge'][0], 'typical_charge_max': d['typical_charge'][1],
        } for code, d in CPT_CODES.items()])
        payers = pd.DataFrame([{
            'payer_id': f'PAY_{i:04d}', 'payer_name': p['payer_name'], 'payer_type': p['payer_type'],
            'reimbursement_rate': p['reimbursement_rate'], 'is_active': True,
        } for i, p in enumerate(PAYERS, 1)])
        return diagnoses, procedures, payers

    def iter_patient_batches(self, hospitals: pd.DataFrame, batch_size: int = DEFAULT_BATCH_SIZE):
        """Yield patients in batches of whole hospitals; records hospital membership.

        batch_size bounds the rows of a batch *including* its per-patient child tables,
        using self.rows_per_patient (refined by the caller from written batches).
        """
        pending, pending_rows = [], 0
        for h in hospitals.itertuples(index=False):
            cfg = self.distribution[h.hospital_type]
            n = int(self.rng.integers(cfg['patients'][0], cfg['patients'][1] + 1))
            pending.append((h, n))
            pending_rows += n
            if pending_rows * self.rows_per_patient >= batch_size:
                yield self._generate_patients(pending)
                pending, pending_rows = [], 0
        if pending:
            yield self._generate_patients(pending)
        self._samplers.pop('patients', None)

    def generate_patients(self, hospitals: pd.DataFrame) -> pd.DataFrame:
        return pd.concat(list(self.iter_patient_batches(hospitals)), ignore_index=True)

    def _generate_patients(self, hospital_counts) -> pd.DataFrame:
        counts = np.array([n for _, n in hospital_counts])
        total = int(counts.sum())
        hosp = np.repeat(np.array([h.hospital_id for h, _ in hospital_counts], dtype=object), counts)
        contract = np.repeat(np.array([np.datetime64(pd.Timestamp(h.contract_start_date), 'D')
                                       for h, _ in hospital_counts]), counts)
        start = self._counters['PAT_'] + 1
        ids = self._next_ids('PAT_', total, 10)
        nums = np.arange(start, start + total)
        gender = self._pick(['M', 'F', 'Other'], total)
        first = np.where(gender == 'M', self._pick(self._pool('first_male'), total),
                         self._pick(self._pool('first_female'), total))
        as_of = np.datetime64(self.as_of.normalize(), 'D')
        for hospital_id, patient_ids in pd.Series(ids).groupby(hosp):
            self.hospital_patients[hospital_id].extend(patient_ids.tolist())
        return pd.DataFrame({
            'patient_id': ids,
            'hospital_id': hosp,
            'mrn': concat_str(hosp, '-', pd.Series(nums).astype(str).str.zfill(8).to_numpy()),
            'ssn_hash': short_hash('SSN', nums),
            'first_name': first,
            'last_name': self._pick(self._pool('last'), total),
            'date_of_birth': as_of - (self.rng.random(total) * 95 * 365.25).astype('timedelta64[D]'),
            'gender': gender,
            'race': self._pick(['White', 'Black', 'Asian', 'Hispanic', 'Other', 'Unknown'], total),
            'ethnicity': self._pick(['Hispanic or Latino', 'Not Hispanic or Latino', 'Unknown'], total),
            'zip_code': self._pick(self._pool('zip'), total),
            'phone_number_hash': short_hash('PHONE', nums),
            'email_hash': short_hash('EMAIL', nums),
            'primary_language': self._pick(['English', 'Spanish', 'Chinese', 'Other'], total),
            'marital_status': self._pick(['Single', 'Married', 'Divorced', 'Widowed'], total),
            'first_encounter_date': contract + self.rng.integers(0, 366, total).astype('timedelta64[D]'),
        })

    # -- per-patient tables ---------------------------------------------------------

    def _days_before_as_of(self, low: int, high: int, n: int) -> np.ndarray:
        return np.datetime64(self.as_of.normalize(), 'D') - self.rng.integers(low, high + 1, n).astype('timedelta64[D]')

    def generate_patient_allergies(self, patients: pd.DataFrame) -> pd.DataFrame:
        has = self.rng.random(len(patients)) < 0.40
        counts = np.where(has, self.rng.choice([1, 2, 3], size=len(patients), p=[0.70, 0.25, 0.05]), 0)
        parent, _ = expand(counts)
        n = len(parent)
        if n == 0:
            return pd.DataFrame()
        hosp = patients['hospital_id'].to_numpy()[parent]
        allergen_idx = self.rng.integers(0, len(COMMON_ALLERGENS), n)
        names = np.array([a['name'] for a in COMMON_ALLERGENS], dtype=object)[allergen_idx]
        severity = np.empty(n, dtype=object)
        reaction = np.empty(n, dtype=object)
        for i, allergen in enumerate(COMMON_ALLERGENS):
            mask = allergen_idx == i
            severity[mask] = self._pick(allergen['severity'], int(mask.sum()))
            reaction[mask] = self._pick(allergen['reactions'], int(mask.sum()))
        start = self._counters['ALG_'] + 1
        return pd.DataFrame({
            'allergy_id': self._next_ids('ALG_', n),
            'hospital_id': hosp,
            'patient_id': patients['patient_id'].to_numpy()[parent],
            'documented_by_provider_id': self._sampler('providers').sample(hosp, self.rng),
            'allergen_type': np.where(np.isin(names, list(DRUG_ALLERGENS)), 'DRUG', 'FOOD'),
            'allergen_code': concat_str('ALLG-', np.arange(start, start + n)),
            'allergen_name': names,
            'reaction_type': reaction,
            'severity': severity,
            'allergy_status': 'ACTIVE',
            'onset_date': self._days_before_as_of(30, 3650, n),
            'resolution_date': None,
            'documentation_date': self._days_before_as_of(1, 365, n),
            'clinical_notes': concat_str('Patient reports ', pd.Series(reaction).str.lower().to_numpy(), ' with ', names),
        })

    def generate_problem_list(self, patients: pd.DataFrame) -> pd.DataFrame:
        counts = self.rng.choice([0, 1, 2, 3, 4, 5], size=len(patients), p=[0.20, 0.30, 0.25, 0.15, 0.07, 0.03])
        parent, _ = expand(counts)
        n = len(parent)
        if n == 0:
            return pd.DataFrame()
        hosp = patients['hospital_id'].to_numpy()[parent]
        dx = self.rng.integers(0, len(CHRONIC_DIAGNOSES), n)
        codes, desc, chronic, sev = (np.array(col, dtype=object)[dx] for col in zip(*CHRONIC_DIAGNOSES))
        status = self._pick(['ACTIVE', 'RESOLVED'], n, p=[0.80, 0.20])
        onset = self._days_before_as_of(365, 3650, n)
        as_of = np.datetime64(self.as_of.normalize(), 'D')
        resolved_after = (self.rng.random(n) * (as_of - onset).astype(np.int64)).astype('timedelta64[D]')
        return pd.DataFrame({
            'problem_id': self._next_ids('PROB_', n),
            'hospital_id': hosp,
            'patient_id': patients['patient_id'].to_numpy()[parent],
            'documented_by_provider_id': self._sampler('providers').sample(hosp, self.rng),
            'diagnosis_code': codes,
            'diagnosis_description': desc,
            'problem_status': status,
            'onset_date': onset,
            'resolution_date': np.where(status == 'RESOLVED', onset + resolved_after, np.datetime64('NaT')),
            'last_reviewed_date': self._days_before_as_of(0, 180, n),
            'severity': sev,
            'is_chronic': chronic.astype(bool),
            'is_primary_diagnosis': self.rng.random(n) < 0.3,
            'documentation_date': self._days_before_as_of(365, 3650, n),
            'clinical_notes': concat_str('Active management of ', pd.Series(desc).str.lower().to_numpy()),
        })

    def generate_patient_coverage(self, patients: pd.DataFrame, payers: pd.DataFrame) -> pd.DataFrame:
        counts = self.rng.choice([0, 1, 2], size=len(patients), p=[0.10, 0.75, 0.15])
        parent, position = expand(counts)
        n = len(parent)
        if n == 0:
            return pd.DataFrame()
        self_relationship = self.rng.random(n) < 0.7
        return pd.DataFrame({
            'coverage_id': self._next_ids('COV_', n),
            'hospital_id': patients['hospital_id'].to_numpy()[parent],
            'patient_id': patients['patient_id'].to_numpy()[parent],
            'payer_id': self._pick(payers['payer_id'], n),
            'policy_number': concat_str('POL-', self.rng.integers(100000, 1000000, n)),
            'group_number': concat_str('GRP-', self.rng.integers(1000, 10000, n)),
            'subscriber_id': concat_str('SUB-', self.rng.integers(100000, 1000000, n)),
            'subscriber_name': concat_str(self._pick(self._pool('first'), n), ' ', self._pick(self._pool('last'), n)),
            'subscriber_relationship': np.where(self_relationship, 'SELF',
                                                self._pick(['SPOUSE', 'CHILD', 'PARENT'], n)),
            'effective_date': self._days_before_as_of(0, 730, n),
            'termination_date': None,
            'coverage_status': 'ACTIVE',
            'plan_type': self._pick(['HMO', 'PPO', 'EPO', 'POS'], n),
            'coverage_level': self._pick(['Individual', 'Family'], n),
            'deductible_amount': self._pick([500, 1000, 2500, 5000], n),
            'deductible_met_amount': np.round(self.rng.uniform(0, 2000, n), 2),
            'out_of_pocket_max': self._pick([3000, 5000, 7500, 10000], n),
            'out_of_pocket_met': np.round(self.rng.uniform(0, 3000, n), 2),
            'copay_amount': self._pick([20, 30, 40, 50], n),
            'coinsurance_pct': self._pick([0.10, 0.20, 0.30], n),
            'coverage_priority': position + 1,
        })

    def generate_sdoh_screenings(self, patients: pd.DataFrame) -> pd.DataFrame:
        mask = self.rng.random(len(patients)) < 0.30
        n = int(mask.sum())
        if n == 0:
            return pd.DataFrame()
        r = lambda p: self.rng.random(n) < p  # noqa: E731
        return pd.DataFrame({
            'screening_id': self._next_ids('SDOH_', n),
            'hospital_id': patients['hospital_id'].to_numpy()[mask],
            'patient_id': patients['patient_id'].to_numpy()[mask],
            'encounter_id': None,
            'screening_date': self._days_before_as_of(0, 365, n),
            'screening_tool_name': 'PRAPARE',
            'housing_status': self._pick(['STABLE', 'UNSTABLE', 'HOMELESS'], n),
            'housing_concerns': r(0.15),
            'food_insecurity_flag': r(0.20),
            'difficulty_affording_food': r(0.20),
            'transportation_barriers': r(0.25),
            'difficulty_paying_utilities': r(0.18),
            'difficulty_affording_medications': r(0.15),
            'social_isolation_score': self.rng.integers(0, 11, n),
            'safety_concerns': r(0.10),
            'intimate_partner_violence_screen': r(0.05),
            'employment_status': self._pick(['Employed Full-time', 'Unemployed', 'Retired', 'Disabled'], n),
            'highest_education_level': self._pick(['High School', 'Some College', 'Bachelor', 'Graduate'], n),
            'health_literacy_score': self.rng.integers(0, 11, n),
            'referrals_text': nullable(np.full(n, 'Social services referral provided', dtype=object), r(0.20)),
        })

    # -- encounters ---------------------------------------------------------------

    def build_encounters(self, hospital_ids: np.ndarray, admissions: np.ndarray) -> pd.DataFrame:
        """Encounters for the given (hospital, admission time) pairs, in admission order.

        Patients, providers and facilities are drawn from each encounter's own
        hospital. Readmission flags use the patient's last inpatient discharge,
        carried across batches.
        """
        order = np.argsort(admissions, kind='stable')
        hosp = np.asarray(hospital_ids, dtype=object)[order]
        admission = np.asarray(admissions, dtype='datetime64[s]')[order]
        n = len(hosp)
        rng = self.rng

        enc_type = ENCOUNTER_TYPES[rng.choice(4, size=n, p=ENCOUNTER_TYPE_WEIGHTS)]
        is_ip, is_obs, is_ed = enc_type == 'Inpatient', enc_type == 'Observation', enc_type == 'Emergency'
        los_days = np.zeros(n, dtype=np.int64)
        los_days[is_ip] = np.clip(rng.lognormal(1.2, 0.8, int(is_ip.sum())).astype(np.int64), 1, 365)
        los_days[is_obs] = rng.integers(0, 3, int(is_obs.sum()))
        los_days[is_ed] = (rng.random(int(is_ed.sum())) < 0.25).astype(np.int64)
        discharge = admission + los_days * DAY + rng.integers(0, 24, n) * HOUR
        los = np.round((discharge - admission) / DAY, 2)

        charges = np.round(rng.uniform(100, 800, n), 2)  # outpatient
        charges[is_ip] = np.round(rng.uniform(2000, 5000, int(is_ip.sum())) * np.maximum(los[is_ip], 1), 2)
        charges[is_ed] = np.round(rng.uniform(500, 3000, int(is_ed.sum())), 2)
        charges[is_obs] = np.round(rng.uniform(1000, 2500, int(is_obs.sum())), 2)

        patients = self._sampler('patients').sample(hosp, rng)
        facility_keys = concat_str(hosp, '|', enc_type)
        df = pd.DataFrame({
            'encounter_id': self._next_ids('ENC_', n),
            'hospital_id': hosp,
            'patient_id': patients,
            'provider_id': self._sampler('providers').sample(hosp, rng),
            'facility_id': self._samplers['facilities'].sample(facility_keys, rng),
            'admission_date': admission,
            'discharge_date': discharge,
            'length_of_stay': los,
            'encounter_type': enc_type,
            'admission_source': self._pick(ADMISSION_TYPES, n),
            'discharge_disposition': self._pick(DISCHARGE_DISPOSITIONS, n),
            'primary_diagnosis_code': self._pick(list(ICD10_CODES), n),
            'total_charges': charges,
            'is_readmission': self._readmission_flags(patients, admission, discharge, is_ip),
            '_source_updated_at': admission,
        })
        return df

    def _readmission_flags(self, patients, admission, discharge, is_ip) -> np.ndarray:
        """Readmission = previous inpatient discharge 1-30 days before this inpatient admission.

        Constant-time per encounter: keeps only each patient's last inpatient discharge.
        Requires encounters to be processed in admission order (build_encounters sorts).
        """
        flags = np.zeros(len(patients), dtype=bool)
        adm_s = admission.astype(np.int64)
        dis_s = discharge.astype(np.int64)
        last = self.last_inpatient_discharge
        for i in np.flatnonzero(is_ip):
            patient = patients[i]
            previous = last.get(patient)
            if previous is not None:
                days = (adm_s[i] - previous) // 86400
                flags[i] = 1 <= days <= 30
            last[patient] = dis_s[i]
        return flags

    def iter_encounter_batches(self, hospitals: pd.DataFrame, batch_size: int = DEFAULT_BATCH_SIZE):
        """Yield encounters for [start_date, end_date] in chronological day-chunks.

        batch_size bounds the rows of a batch *including* all encounter-derived tables:
        days per chunk = batch_size / (expected daily encounters * rows per encounter),
        where self.rows_per_encounter is re-estimated by the caller after every batch.
        """
        daily = expected_daily_encounters({t: {**c, 'count': int((hospitals.hospital_type == t).sum())}
                                           for t, c in self.distribution.items()})
        all_days = pd.date_range(self.start_date.normalize(), self.end_date.normalize(), freq='D')
        lo = hospitals['hospital_type'].map(lambda t: self.distribution[t]['daily_encounters'][0]).to_numpy()
        hi = hospitals['hospital_type'].map(lambda t: self.distribution[t]['daily_encounters'][1]).to_numpy()
        contract = pd.to_datetime(hospitals['contract_start_date']).to_numpy(dtype='datetime64[s]')
        hospital_ids = hospitals['hospital_id'].to_numpy(dtype=object)

        i = 0
        while i < len(all_days):
            days_per_batch = max(1, int(batch_size // max(daily * self.rows_per_encounter, 1)))
            days = all_days[i:i + days_per_batch].to_numpy(dtype='datetime64[s]')
            i += days_per_batch
            counts = self.rng.integers(lo, hi + 1, size=(len(days), len(hospital_ids)))
            counts = counts * (days[:, None] >= contract[None, :])
            flat = counts.ravel()
            hosp = np.repeat(np.tile(hospital_ids, len(days)), flat)
            day = np.repeat(np.repeat(days, len(hospital_ids)), flat)
            admission = day + self.rng.integers(0, 24 * 60, len(day)) * MINUTE
            yield self.build_encounters(hosp, admission)

    def generate_encounters(self, hospitals: pd.DataFrame, *_unused) -> pd.DataFrame:
        return pd.concat(list(self.iter_encounter_batches(hospitals)), ignore_index=True)

    # -- encounter-derived tables (vectorized) -----------------------------------------

    def generate_billing_transactions(self, encounters: pd.DataFrame, payers: pd.DataFrame) -> pd.DataFrame:
        n = len(encounters)
        rng = self.rng
        payer_idx = rng.integers(0, len(payers), n)
        rate = payers['reimbursement_rate'].to_numpy(dtype=float)[payer_idx]
        charge = encounters['total_charges'].to_numpy(dtype=float)
        payment = np.round(charge * rate, 2)
        adjustment = np.round(charge - payment, 2)
        status = self._pick(['Paid', 'Partial', 'Denied', 'Pending'], n, p=[0.40, 0.05, 0.10, 0.45])
        discharge = encounters['discharge_date'].to_numpy(dtype='datetime64[s]')
        return pd.DataFrame({
            'transaction_id': self._next_ids('TXN_', n),
            'hospital_id': encounters['hospital_id'].to_numpy(),
            'encounter_id': encounters['encounter_id'].to_numpy(),
            'patient_id': encounters['patient_id'].to_numpy(),
            'payer_id': payers['payer_id'].to_numpy(dtype=object)[payer_idx],
            'transaction_date': discharge + rng.integers(1, 46, n) * DAY,
            'charge_amount': charge,
            'payment_amount': np.where(np.isin(status, ['Paid', 'Partial']), payment, 0.0),
            'adjustment_amount': adjustment,
            'denial_reason': nullable(self._pick(DENIAL_REASONS, n), status == 'Denied'),
            'payment_status': status,
        })

    def generate_vital_signs(self, encounters: pd.DataFrame) -> pd.DataFrame:
        rng = self.rng
        enc_type = encounters['encounter_type'].to_numpy()
        los = encounters['length_of_stay'].to_numpy(dtype=float)
        counts = np.ones(len(encounters), dtype=np.int64)
        is_ed, is_ip = enc_type == 'Emergency', enc_type == 'Inpatient'
        counts[is_ed] = rng.integers(3, 9, int(is_ed.sum()))
        counts[is_ip] = np.maximum(1, los[is_ip].astype(np.int64) * rng.integers(2, 5, int(is_ip.sum())))
        parent, position = expand(counts)
        n = len(parent)
        if n == 0:
            return pd.DataFrame()

        # per-encounter body measurements, constant across that encounter's readings
        weight = np.maximum(40, rng.normal(75, 15, len(encounters)))[parent]
        height = np.maximum(140, rng.normal(170, 10, len(encounters)))[parent]
        offset_hours = position * (los[parent] * 24 / counts[parent])
        admission = encounters['admission_date'].to_numpy(dtype='datetime64[s]')[parent]
        sbp = np.clip(rng.normal(120, 15, n).astype(np.int64), 70, 200)
        dbp = np.clip(rng.normal(80, 10, n).astype(np.int64), 40, 120)
        return pd.DataFrame({
            'vital_id': self._next_ids('VIT_', n),
            'hospital_id': encounters['hospital_id'].to_numpy()[parent],
            'encounter_id': encounters['encounter_id'].to_numpy()[parent],
            'patient_id': encounters['patient_id'].to_numpy()[parent],
            'measurement_datetime': admission + (offset_hours * 3600).astype(np.int64) * SECOND,
            'temperature_f': np.round(rng.normal(98.6, 1.0, n), 1),
            'heart_rate_bpm': np.clip(rng.normal(75, 12, n).astype(np.int64), 40, 180),
            'respiratory_rate': np.clip(rng.normal(16, 3, n).astype(np.int64), 8, 40),
            'systolic_bp': sbp,
            'diastolic_bp': dbp,
            'oxygen_saturation_pct': np.clip(rng.normal(97, 2, n).astype(np.int64), 85, 100),
            'weight_kg': np.round(weight, 1),
            'height_cm': np.round(height, 1),
            'bmi': np.round(weight / (height / 100) ** 2, 1),
            'pain_score': np.where(rng.random(n) < 0.4, rng.integers(0, 11, n), 0),
            'map_mmhg': ((sbp + 2 * dbp) / 3).astype(np.int64),
            'position': self._pick(['SITTING', 'STANDING', 'SUPINE'], n),
            'measured_by_role': self._pick(['RN', 'MA', 'MD'], n),
        })

    def generate_clinical_orders(self, encounters: pd.DataFrame) -> pd.DataFrame:
        rng = self.rng
        enc_type = encounters['encounter_type'].to_numpy()
        ranges = {'Emergency': (5, 15), 'Inpatient': (10, 30), 'Observation': (5, 12), 'Outpatient': (1, 5)}
        counts = np.full(len(encounters), 3, dtype=np.int64)
        for t, (lo, hi) in ranges.items():
            mask = enc_type == t
            counts[mask] = rng.integers(lo, hi + 1, int(mask.sum()))
        parent, _ = expand(counts)
        n = len(parent)
        if n == 0:
            return pd.DataFrame()

        los = encounters['length_of_stay'].to_numpy(dtype=float)[parent]
        admission = encounters['admission_date'].to_numpy(dtype='datetime64[s]')[parent]
        order_time = admission + (rng.random(n) * np.minimum(24, los * 24) * 3600).astype(np.int64) * SECOND
        order_type = self._pick(['LAB', 'RADIOLOGY', 'MEDICATION', 'PROCEDURE'], n, p=[0.40, 0.20, 0.30, 0.10])
        lab, med = order_type == 'LAB', order_type == 'MEDICATION'
        other = ~(lab | med)
        n_lab, n_med, n_other = int(lab.sum()), int(med.sum()), int(other.sum())
        provider = encounters['provider_id'].to_numpy()[parent]

        obj = lambda: np.full(n, None, dtype=object)  # noqa: E731
        code, desc, specimen = obj(), obj(), obj()
        med_name, dose, route, frequency, status = obj(), obj(), obj(), obj(), obj()
        scheduled = np.full(n, np.datetime64('NaT'), dtype='datetime64[s]')
        completed, collection = scheduled.copy(), scheduled.copy()
        duration = np.full(n, np.nan)

        lab_codes = np.array(list(LAB_TESTS), dtype=object)
        lab_pick = lab_codes[rng.integers(0, len(lab_codes), n_lab)]
        code[lab], desc[lab] = lab_pick, pd.Series(lab_pick).map(lambda c: LAB_TESTS[c]['name']).to_numpy()
        specimen[lab] = self._pick(['Blood', 'Serum', 'Urine'], n_lab)
        scheduled[lab] = order_time[lab] + HOUR
        completed[lab] = order_time[lab] + (rng.uniform(2, 6, n_lab) * 3600).astype(np.int64) * SECOND
        collection[lab] = order_time[lab] + 30 * MINUTE
        status[lab] = 'COMPLETED'

        med_idx = rng.integers(0, len(MEDICATIONS), n_med)
        med_rows = np.flatnonzero(med)
        code[med] = concat_str('MED-', rng.integers(1000, 10000, n_med))
        names = np.array([m['name'] for m in MEDICATIONS], dtype=object)[med_idx]
        desc[med], med_name[med] = names, names
        dose[med] = np.array([m['dose'] for m in MEDICATIONS], dtype=object)[med_idx]
        frequency[med] = np.array([m['frequency'] for m in MEDICATIONS], dtype=object)[med_idx]
        for i, m in enumerate(MEDICATIONS):
            rows = med_rows[med_idx == i]
            route[rows] = self._pick(m['routes'], len(rows))
        scheduled[med] = order_time[med]
        completed[med] = order_time[med] + 30 * MINUTE
        status[med] = 'COMPLETED'
        duration[med] = rng.integers(1, 15, n_med)

        other_type = order_type[other]
        code[other] = concat_str(other_type, '-', rng.integers(1000, 10000, n_other))
        desc[other] = concat_str(other_type, ' Study')
        scheduled[other] = order_time[other] + 2 * HOUR
        completed[other] = order_time[other] + 4 * HOUR
        status[other] = self._pick(['COMPLETED', 'IN_PROGRESS'], n_other)

        return pd.DataFrame({
            'order_id': self._next_ids('ORD_', n),
            'hospital_id': encounters['hospital_id'].to_numpy()[parent],
            'encounter_id': encounters['encounter_id'].to_numpy()[parent],
            'patient_id': encounters['patient_id'].to_numpy()[parent],
            'provider_id': provider,
            'ordering_provider_id': provider,
            'order_type': order_type,
            'order_datetime': order_time,
            'priority': self._pick(['ROUTINE', 'URGENT', 'STAT'], n, p=[0.70, 0.20, 0.10]),
            'performing_location': np.where(lab, 'Laboratory', 'Radiology'),
            'result_id': None,
            '_source_file': 'synthetic_data',
            'order_code': code,
            'order_description': desc,
            'specimen_type': specimen,
            'scheduled_datetime': scheduled,
            'completed_datetime': completed,
            'order_status': status,
            'collection_datetime': collection,
            'medication_name': med_name,
            'dose': dose,
            'route': route,
            'frequency': frequency,
            'duration_days': duration,
        })

    def generate_clinical_results(self, orders: pd.DataFrame) -> pd.DataFrame:
        labs = orders[(orders['order_type'] == 'LAB') & (orders['order_status'] == 'COMPLETED')
                      & orders['order_code'].isin(list(LAB_TESTS))]
        n = len(labs)
        if n == 0:
            return pd.DataFrame()
        codes = labs['order_code'].to_numpy()
        info = pd.Series(codes).map(LAB_TESTS)
        low = info.map(lambda t: t['range'][0]).to_numpy(dtype=float)
        high = info.map(lambda t: t['range'][1]).to_numpy(dtype=float)
        names = info.map(lambda t: t['name']).to_numpy()
        value = self.rng.normal((low + high) / 2, (high - low) / 4)
        completed = labs['completed_datetime'].to_numpy(dtype='datetime64[s]')
        collected = labs['collection_datetime'].to_numpy(dtype='datetime64[s]')
        collected = np.where(np.isnat(collected), labs['order_datetime'].to_numpy(dtype='datetime64[s]'), collected)
        return pd.DataFrame({
            'result_id': self._next_ids('RES_', n),
            'hospital_id': labs['hospital_id'].to_numpy(),
            'order_id': labs['order_id'].to_numpy(),
            'patient_id': labs['patient_id'].to_numpy(),
            'encounter_id': labs['encounter_id'].to_numpy(),
            'interpreting_provider_id': labs['provider_id'].to_numpy(),
            'result_type': 'LAB',
            'test_code': codes,
            'test_name': names,
            'component_code': codes,
            'component_name': names,
            'result_value': np.char.mod('%.2f', value).astype(object),
            'result_value_numeric': np.round(value, 2),
            'result_units': info.map(lambda t: t['units']).to_numpy(),
            'reference_range_low': low,
            'reference_range_high': high,
            'abnormal_flag': np.where(value < low, 'L', np.where(value > high, 'H', 'N')),
            'result_datetime': completed,
            'collected_datetime': collected,
            'resulted_datetime': completed,
            'result_status': 'FINAL',
            'performing_lab': 'Main Laboratory',
            'imaging_modality': None,
            'impression': None,
            'report_text': None,
        })

    def generate_medication_administration(self, orders: pd.DataFrame) -> pd.DataFrame:
        meds = orders[orders['order_type'] == 'MEDICATION']
        rng = self.rng
        parent, position = expand(rng.integers(1, 11, len(meds)))
        n = len(parent)
        if n == 0:
            return pd.DataFrame()
        hosp = meds['hospital_id'].to_numpy()[parent]
        scheduled = meds['scheduled_datetime'].to_numpy(dtype='datetime64[s]')[parent] + position * 6 * HOUR
        status = self._pick(['GIVEN', 'REFUSED', 'HELD', 'MISSED'], n, p=[0.85, 0.05, 0.05, 0.05])
        adverse = rng.random(n) < 0.02
        witness = self._sampler('providers').sample(hosp, rng)  # same hospital as the administration
        col = lambda c: meds[c].to_numpy()[parent]  # noqa: E731
        return pd.DataFrame({
            'admin_id': self._next_ids('ADM_', n),
            'hospital_id': hosp,
            'encounter_id': col('encounter_id'),
            'patient_id': col('patient_id'),
            'order_id': col('order_id'),
            'medication_name': col('medication_name'),
            'dose': col('dose'),
            'route': col('route'),
            'scheduled_datetime': scheduled,
            'administered_datetime': nat_where(scheduled + rng.integers(-30, 61, n) * MINUTE, status == 'GIVEN'),
            'administered_by_provider_id': col('provider_id'),
            'witnessed_by_provider_id': nullable(witness, rng.random(n) < 0.80),
            'administration_status': status,
            'refusal_reason': nullable(np.full(n, 'Patient declined', dtype=object), status == 'REFUSED'),
            'hold_reason': nullable(np.full(n, 'Clinical hold', dtype=object), status == 'HELD'),
            'barcode_scanned': rng.random(n) < 0.90,
            'adverse_reaction_flag': adverse,
            'reaction_description': nullable(np.full(n, 'Mild rash', dtype=object), adverse),
        })

    # -- care coordination & quality (vectorized) ---------------------------------------

    def _today(self) -> np.datetime64:
        return np.datetime64(self.as_of.normalize(), 'D')

    def generate_quality_measures(self, encounters: pd.DataFrame) -> pd.DataFrame:
        """CMS core-measure records for inpatient/ED encounters in a measure cohort."""
        cohorts = self.QUALITY_MEASURE_COHORTS
        mask = (encounters['encounter_type'].isin(['Inpatient', 'Emergency'])
                & encounters['primary_diagnosis_code'].isin(list(cohorts))).to_numpy()
        n = int(mask.sum())
        if n == 0:
            return pd.DataFrame()
        rng = self.rng
        dx = encounters['primary_diagnosis_code'].to_numpy()[mask]
        attr = lambda i: pd.Series(dx).map({c: v[i] for c, v in cohorts.items()}).to_numpy()  # noqa: E731
        measure_code, measure_name, category, timing_field = attr(0), attr(1), attr(2), attr(3)
        target = pd.Series(dx).map({c: v[4] for c, v in cohorts.items()}).to_numpy(dtype=float)
        admission = encounters['admission_date'].to_numpy(dtype='datetime64[s]')[mask]

        timed = ~np.isnan(target)
        minutes = np.where(timed, np.maximum(5, rng.lognormal(np.log(np.nan_to_num(target, nan=1) * 0.75), 0.45)),
                           np.nan).astype(float)
        minutes = np.where(timed, np.floor(minutes), np.nan)
        met = np.where(timed, minutes <= target, rng.random(n) < 0.88)
        excluded = rng.random(n) < 0.08
        compliant = ~excluded & met
        component_ts = np.where(timed, admission + np.nan_to_num(minutes).astype(np.int64) * MINUTE,
                                admission + rng.integers(1, 25, n) * HOUR)
        timing = {col: np.where(timing_field == col, minutes, np.nan)
                  for col in ('door_to_antibiotic_minutes', 'door_to_balloon_minutes', 'door_to_needle_minutes')}
        year = admission.astype('datetime64[Y]').astype(int) + 1970
        quarter = (admission.astype('datetime64[M]').astype(int) % 12) // 3 + 1
        return pd.DataFrame({
            'measure_id': self._next_ids('QM_', n),
            'hospital_id': encounters['hospital_id'].to_numpy()[mask],
            'encounter_id': encounters['encounter_id'].to_numpy()[mask],
            'patient_id': encounters['patient_id'].to_numpy()[mask],
            'measure_code': measure_code,
            'measure_name': measure_name,
            'measure_category': category,
            'numerator_eligible': compliant,
            'denominator_eligible': True,
            'exclusion_applied': excluded,
            'exclusion_reason': nullable(self._pick(['Comfort measures only', 'Transfer from another acute facility',
                                                     'Patient refused treatment'], n), excluded),
            **timing,
            'metric_component': np.where(timed, timing_field, 'process_documented'),
            'component_value': np.where(timed, pd.Series(np.nan_to_num(minutes).astype(np.int64)).astype(str).to_numpy(),
                                        np.where(met, 'Y', 'N')).astype(object),
            'component_timestamp': component_ts,
            'compliance_flag': compliant,
            'reporting_quarter': concat_str(year, 'Q', quarter),
            'reporting_year': year,
        })

    def generate_care_plans(self, encounters: pd.DataFrame) -> pd.DataFrame:
        """Multidisciplinary care plans for ~70% of inpatient stays."""
        rng = self.rng
        mask = (encounters['encounter_type'] == 'Inpatient').to_numpy()
        mask &= rng.random(len(encounters)) < 0.70
        n = int(mask.sum())
        if n == 0:
            return pd.DataFrame()
        hosp = encounters['hospital_id'].to_numpy()[mask]
        category = pd.Series(encounters['primary_diagnosis_code'].to_numpy()[mask]).map(
            {c: d['category'] for c, d in ICD10_CODES.items()})
        template = lambda i: category.map({k: v[i] for k, v in self.CARE_PLAN_TEMPLATES.items()}).fillna(  # noqa: E731
            self.DEFAULT_CARE_PLAN[i]).to_numpy(dtype=object)

        today = self._today()
        start = encounters['admission_date'].to_numpy(dtype='datetime64[s]')[mask].astype('datetime64[D]')
        target = start + self._pick([14, 30, 60, 90], n).astype(np.int64).astype('timedelta64[D]')
        status = self._pick(['ACTIVE', 'COMPLETED', 'DISCONTINUED'], n, p=[0.45, 0.45, 0.10])
        completion = np.clip(target + rng.integers(-10, 11, n).astype('timedelta64[D]'), start, today)
        bucket = rng.choice(3, size=n, p=[0.6, 0.3, 0.1])
        days_ago = np.choose(bucket, [rng.integers(0, 31, n), rng.integers(31, 91, n), rng.integers(91, 181, n)])
        return pd.DataFrame({
            'care_plan_id': self._next_ids('CP_', n),
            'hospital_id': hosp,
            'encounter_id': encounters['encounter_id'].to_numpy()[mask],
            'patient_id': encounters['patient_id'].to_numpy()[mask],
            'problem_description': template(0),
            'goal_description': template(1),
            'intervention_description': template(2),
            'plan_status': status,
            'start_date': start,
            'target_date': target,
            'completion_date': np.where(status == 'COMPLETED', completion, np.datetime64('NaT')),
            'created_by_provider_id': encounters['provider_id'].to_numpy()[mask],
            'assigned_to_provider_ids': self._sampler('providers').sample_distinct(hosp, 3, rng),
            'progress_notes': self._pick(['Progressing toward goal', 'Goal met', 'Slow progress, plan revised',
                                          'No change since last evaluation'], n),
            'last_evaluated_date': np.maximum(today - days_ago.astype('timedelta64[D]'), start),
        })

    def generate_referrals(self, encounters: pd.DataFrame) -> pd.DataFrame:
        """Post-discharge referrals (specialist, home health, SNF, DME)."""
        rng = self.rng
        probability = encounters['encounter_type'].map({'Inpatient': 0.45, 'Emergency': 0.15, 'Outpatient': 0.10})
        mask = (rng.random(len(encounters)) < probability.fillna(0).to_numpy())
        n = int(mask.sum())
        if n == 0:
            return pd.DataFrame()
        hosp = encounters['hospital_id'].to_numpy()[mask]
        dx = pd.Series(encounters['primary_diagnosis_code'].to_numpy()[mask])
        category = dx.map({c: d['category'] for c, d in ICD10_CODES.items()})
        description = dx.map({c: d['description'] for c, d in ICD10_CODES.items()}).fillna('condition')

        ref_type = self._pick(['SPECIALIST', 'HOME_HEALTH', 'SNF', 'DME'], n, p=[0.65, 0.15, 0.10, 0.10])
        urgency = self._pick(['ROUTINE', 'URGENT', 'EMERGENT'], n, p=[0.70, 0.25, 0.05])
        status = self._pick(['PENDING', 'SCHEDULED', 'COMPLETED', 'CANCELLED'], n, p=[0.15, 0.20, 0.55, 0.10])
        referral_date = encounters['discharge_date'].to_numpy(dtype='datetime64[s]')[mask].astype('datetime64[D]')
        lo = np.select([urgency == 'URGENT', urgency == 'EMERGENT'], [1, 0], 7)
        hi = np.select([urgency == 'URGENT', urgency == 'EMERGENT'], [10, 2], 45)
        has_appointment = np.isin(status, ['SCHEDULED', 'COMPLETED'])
        appointment = nat_where(referral_date + rng.integers(lo, hi + 1).astype('timedelta64[D]'), has_appointment)
        future = status == 'COMPLETED'
        future &= appointment > self._today()
        status = np.where(future, 'SCHEDULED', status)  # can't be completed in the future
        completed = status == 'COMPLETED'
        follow_up_required = rng.random(n) < 0.40
        specialist = ref_type == 'SPECIALIST'
        suffix = pd.Series(ref_type).map({'HOME_HEALTH': ' Home Health', 'SNF': ' Skilled Nursing',
                                          'DME': ' Medical Supply'}).fillna('').to_numpy()
        return pd.DataFrame({
            'referral_id': self._next_ids('REF_', n),
            'hospital_id': hosp,
            'patient_id': encounters['patient_id'].to_numpy()[mask],
            'encounter_id': encounters['encounter_id'].to_numpy()[mask],
            'referral_type': ref_type,
            'referring_provider_id': encounters['provider_id'].to_numpy()[mask],
            'referred_to_provider_id': nullable(self._sampler('providers').sample(hosp, rng), specialist),
            'referred_to_facility': nullable(concat_str(self._pick(self._pool('company', 500), n), suffix), ~specialist),
            'specialty': nullable(category.map(self.REFERRAL_SPECIALTIES).fillna('Internal Medicine').to_numpy(),
                                  specialist),
            'referral_status': status,
            'referral_date': referral_date,
            'appointment_date': appointment.astype('datetime64[D]'),
            'completion_date': np.where(completed, appointment, np.datetime64('NaT')).astype('datetime64[D]'),
            'reason_for_referral': concat_str('Follow-up for ', description.str.lower().to_numpy()),
            'diagnosis_codes': dx.to_numpy(),
            'urgency': urgency,
            'follow_up_required': follow_up_required,
            'follow_up_completed': follow_up_required & completed & (rng.random(n) < 0.75),
        })

    def generate_prior_authorizations(self, encounters: pd.DataFrame, billing: pd.DataFrame) -> pd.DataFrame:
        """Payer prior authorizations for ~30% of planned inpatient/outpatient services."""
        rng = self.rng
        payer = encounters['encounter_id'].map(
            billing.drop_duplicates('encounter_id').set_index('encounter_id')['payer_id']).to_numpy()
        mask = encounters['encounter_type'].isin(['Inpatient', 'Outpatient']).to_numpy()
        mask &= pd.notna(payer)
        mask &= rng.random(len(encounters)) < 0.30
        n = int(mask.sum())
        if n == 0:
            return pd.DataFrame()
        cpt = [(code, d['description']) for code, d in CPT_CODES.items() if d.get('category') != 'Emergency']
        service = rng.integers(0, len(cpt), n)
        request = (encounters['admission_date'].to_numpy(dtype='datetime64[s]')[mask].astype('datetime64[D]')
                   - rng.integers(3, 22, n).astype('timedelta64[D]'))
        # auth_status is the payer decision; staging derives is_expired from the dates
        status = self._pick(['APPROVED', 'DENIED', 'PENDING', 'EXPIRED'], n, p=[0.75, 0.12, 0.08, 0.05])
        decision = nat_where(request + rng.integers(1, 15, n).astype('timedelta64[D]'), status != 'PENDING')
        has_effective = np.isin(status, ['APPROVED', 'EXPIRED'])
        effective = nat_where(decision, has_effective)
        expiration = effective + self._pick([30, 60, 90, 180], n).astype(np.int64).astype('timedelta64[D]')
        units = np.where(has_effective, self._pick([1, 1, 1, 6, 12, 24], n).astype(float), np.nan)
        used = np.where(has_effective, np.floor(rng.random(n) * (np.nan_to_num(units) + 1)), np.nan)
        return pd.DataFrame({
            'auth_id': self._next_ids('AUTH_', n),
            'hospital_id': encounters['hospital_id'].to_numpy()[mask],
            'patient_id': encounters['patient_id'].to_numpy()[mask],
            'payer_id': payer[mask],
            'encounter_id': encounters['encounter_id'].to_numpy()[mask],
            'auth_number': concat_str('PA', rng.integers(10_000_000, 100_000_000, n)),
            'auth_type': self._pick(['SERVICE', 'MEDICATION', 'DME'], n, p=[0.75, 0.15, 0.10]),
            'service_code': np.array([c for c, _ in cpt], dtype=object)[service],
            'service_description': np.array([d for _, d in cpt], dtype=object)[service],
            'auth_status': status,
            'request_date': request,
            'decision_date': decision.astype('datetime64[D]'),
            'effective_date': effective.astype('datetime64[D]'),
            'expiration_date': expiration.astype('datetime64[D]'),
            'units_authorized': units,
            'units_used': used,
            'units_remaining': units - used,
            'diagnosis_codes': encounters['primary_diagnosis_code'].to_numpy()[mask],
            'clinical_notes': 'Medical necessity documented per payer criteria',
            'denial_reason': nullable(self._pick(DENIAL_REASONS, n), status == 'DENIED'),
        })

    def generate_encounter_children(self, encounters: pd.DataFrame, payers: pd.DataFrame) -> dict[str, pd.DataFrame]:
        """All tables derived from one batch of encounters."""
        billing = self.generate_billing_transactions(encounters, payers)
        orders = self.generate_clinical_orders(encounters)
        return {
            'billing_transactions': billing,
            'vital_signs': self.generate_vital_signs(encounters),
            'clinical_orders': orders,
            'clinical_results': self.generate_clinical_results(orders),
            'medication_administration': self.generate_medication_administration(orders),
            'quality_measures': self.generate_quality_measures(encounters),
            'care_plans': self.generate_care_plans(encounters),
            'referrals': self.generate_referrals(encounters),
            'prior_authorizations': self.generate_prior_authorizations(encounters, billing),
        }


# ---------------------------------------------------------------------------
# Streaming dataset generation + metrics
# ---------------------------------------------------------------------------

class Metrics:
    """Per-table generation time and rows, plus peak process RSS."""

    def __init__(self):
        self.gen_seconds: dict[str, float] = defaultdict(float)
        self.started = time.perf_counter()
        self.peak_rss = 0
        try:
            import psutil
            self._process = psutil.Process()
        except ImportError:  # optional
            self._process = None

    def timed(self, table: str, fn, *args):
        start = time.perf_counter()
        result = fn(*args)
        self.gen_seconds[table] += time.perf_counter() - start
        return result

    def sample_memory(self) -> None:
        if self._process is not None:
            self.peak_rss = max(self.peak_rss, self._process.memory_info().rss)

    def report(self, writer: TableWriter) -> dict:
        tables = {}
        for table, stats in writer.stats.items():
            gen = self.gen_seconds.get(table, 0.0)
            size = sum(os.path.getsize(p) for p in stats.files if os.path.exists(p))
            tables[table] = {
                'rows': stats.rows, 'batches': stats.batches, 'generate_seconds': round(gen, 2),
                'write_seconds': round(stats.write_seconds, 2),
                'rows_per_second': round(stats.rows / max(gen + stats.write_seconds, 1e-9)),
                'file_mb': round(size / 2 ** 20, 1),
            }
        return {
            'total_rows': sum(t['rows'] for t in tables.values()),
            'elapsed_seconds': round(time.perf_counter() - self.started, 1),
            'peak_rss_mb': round(self.peak_rss / 2 ** 20) if self.peak_rss else None,
            'tables': tables,
        }


def generate_dataset(start_date: str, end_date: str, hospitals: int = DEFAULT_HOSPITALS,
                     batch_size: int = DEFAULT_BATCH_SIZE, seed: int = DEFAULT_SEED,
                     parquet_dir: str | None = 'data_generation/parquet', csv_dir: str | None = None,
                     verbose: bool = True) -> dict:
    """Generate all 21 raw tables, streaming each batch to disk. Returns the metrics report."""
    gen = HealthcareDataGenerator(start_date, end_date, seed=seed,
                                  distribution=scaled_distribution(hospitals), verbose=verbose)
    metrics = Metrics()
    log = gen.log
    log(f'IsoMetrics data generation: {hospitals} hospitals, {start_date} -> {end_date} '
        f'({gen.days} days), batch size {batch_size:,}, seed {seed}')

    with TableWriter(parquet_dir=parquet_dir, csv_dir=csv_dir) as writer:
        hospitals_df = metrics.timed('hospitals', gen.generate_hospitals)
        providers = metrics.timed('providers', gen.generate_providers, hospitals_df)
        facilities = metrics.timed('facilities', gen.generate_facilities, hospitals_df)
        diagnoses, procedures, payers = metrics.timed('reference', gen.generate_reference_tables)
        for table, df in [('hospitals', hospitals_df), ('providers', providers), ('facilities', facilities),
                          ('diagnoses', diagnoses), ('procedures', procedures), ('payers', payers)]:
            writer.write(table, df)
        log(f'  master data: {len(hospitals_df)} hospitals, {len(providers):,} providers, '
            f'{len(facilities)} facilities')

        patient_iter = gen.iter_patient_batches(hospitals_df, batch_size)
        while True:
            patients = metrics.timed('patients', next, patient_iter, None)
            if patients is None:
                break
            rows_before = sum(st.rows for st in writer.stats.values())
            writer.write('patients', patients)
            writer.write('patient_allergies', metrics.timed('patient_allergies', gen.generate_patient_allergies, patients))
            writer.write('problem_list', metrics.timed('problem_list', gen.generate_problem_list, patients))
            writer.write('patient_coverage',
                         metrics.timed('patient_coverage', gen.generate_patient_coverage, patients, payers))
            writer.write('sdoh_screenings', metrics.timed('sdoh_screenings', gen.generate_sdoh_screenings, patients))
            metrics.sample_memory()
            gen.rows_per_patient = max(1.0, (sum(st.rows for st in writer.stats.values()) - rows_before) / len(patients))
            del patients
        log(f"  patients: {writer.stats['patients'].rows:,}")

        encounter_iter = gen.iter_encounter_batches(hospitals_df, batch_size)
        batch_no = 0
        while True:
            encounters = metrics.timed('encounters', next, encounter_iter, None)
            if encounters is None:
                break
            batch_no += 1
            rows_before = sum(st.rows for st in writer.stats.values())
            writer.write('encounters', encounters)
            # Each child table is written as soon as it exists and then dropped, so a batch
            # never holds all nine at once. billing is kept for prior auths, orders for
            # results and medication administration.
            billing = metrics.timed('billing_transactions', gen.generate_billing_transactions, encounters, payers)
            writer.write('billing_transactions', billing)
            orders = metrics.timed('clinical_orders', gen.generate_clinical_orders, encounters)
            writer.write('clinical_orders', orders)
            for table, fn, args in [
                ('clinical_results', gen.generate_clinical_results, (orders,)),
                ('medication_administration', gen.generate_medication_administration, (orders,)),
            ]:
                writer.write(table, metrics.timed(table, fn, *args))
            del orders
            for table, fn, args in [
                ('prior_authorizations', gen.generate_prior_authorizations, (encounters, billing)),
                ('vital_signs', gen.generate_vital_signs, (encounters,)),
                ('quality_measures', gen.generate_quality_measures, (encounters,)),
                ('care_plans', gen.generate_care_plans, (encounters,)),
                ('referrals', gen.generate_referrals, (encounters,)),
            ]:
                writer.write(table, metrics.timed(table, fn, *args))
            del billing
            metrics.sample_memory()
            batch_rows = sum(st.rows for st in writer.stats.values()) - rows_before
            gen.rows_per_encounter = max(1.0, batch_rows / max(len(encounters), 1))
            log(f"  batch {batch_no}: {len(encounters):,} encounters, {batch_rows:,} rows "
                f"(total {writer.stats['encounters'].rows:,} encounters, {time.perf_counter() - metrics.started:,.0f}s)")
            del encounters

    report = metrics.report(writer)
    report.update({'hospitals': hospitals, 'start_date': str(start_date), 'end_date': str(end_date),
                   'batch_size': batch_size, 'seed': seed})
    return report


def print_report(report: dict) -> None:
    print('\n' + '=' * 86)
    print(f"{'table':<28}{'rows':>14}{'gen s':>9}{'write s':>9}{'rows/s':>12}{'MB':>9}")
    print('-' * 86)
    for table, t in sorted(report['tables'].items(), key=lambda kv: -kv[1]['rows']):
        print(f"{table:<28}{t['rows']:>14,}{t['generate_seconds']:>9.1f}{t['write_seconds']:>9.1f}"
              f"{t['rows_per_second']:>12,}{t['file_mb']:>9.1f}")
    print('-' * 86)
    print(f"{'TOTAL':<28}{report['total_rows']:>14,}   elapsed {report['elapsed_seconds']:,.1f}s"
          f"   peak RAM {report['peak_rss_mb']} MB")
    print('=' * 86)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--start-date', default='2025-01-01')
    span = parser.add_mutually_exclusive_group()
    span.add_argument('--end-date', help='Inclusive end date')
    span.add_argument('--days', type=int, help='Number of days (default 30)')
    span.add_argument('--target-encounters', type=int,
                      help='Size the date range to produce about this many encounters')
    parser.add_argument('--hospitals', type=int, default=DEFAULT_HOSPITALS, help='Number of tenants (default 100)')
    parser.add_argument('--batch-size', type=int, default=DEFAULT_BATCH_SIZE,
                        help='Max rows per batch, counting child tables; bounds peak memory (default 500,000)')
    parser.add_argument('--seed', type=int, default=DEFAULT_SEED)
    parser.add_argument('--format', choices=['parquet', 'csv', 'both'], default='parquet')
    parser.add_argument('--parquet-dir', default='data_generation/parquet')
    parser.add_argument('--csv-dir', default='data_generation/2025')
    args = parser.parse_args(argv)

    start = pd.Timestamp(args.start_date)
    if args.end_date:
        end = pd.Timestamp(args.end_date)
    else:
        if args.target_encounters:
            daily = expected_daily_encounters(scaled_distribution(args.hospitals))
            days = math.ceil(args.target_encounters / daily)
        else:
            days = args.days or 30
        end = start + pd.Timedelta(days=days - 1)

    report = generate_dataset(
        start_date=start.date().isoformat(), end_date=end.date().isoformat(), hospitals=args.hospitals,
        batch_size=args.batch_size, seed=args.seed,
        parquet_dir=args.parquet_dir if args.format in ('parquet', 'both') else None,
        csv_dir=args.csv_dir if args.format in ('csv', 'both') else None)
    print_report(report)
    out_dir = args.parquet_dir if args.format != 'csv' else args.csv_dir
    with open(os.path.join(out_dir, 'generation_report.json'), 'w', encoding='utf-8') as f:
        json.dump(report, f, indent=2)
    print(f'Report: {os.path.join(out_dir, "generation_report.json")}')
    print('All PHI is synthetic.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
