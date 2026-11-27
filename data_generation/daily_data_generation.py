"""
Incremental batch generator for the scheduled pipeline.

Generates one time window of *transactional* data for the tenants that already
exist in Snowflake: encounters plus everything derived from them (billing,
vitals, orders, results, medication administration, quality measures, care
plans, referrals, prior authorizations). Master data (hospitals, patients,
providers, facilities, allergies, problem lists, coverage, SDOH) is created
once by generate_data.py and only read here.

Guarantees the scheduled pipeline relies on:
- Tenant-consistent: every encounter uses a patient, provider and facility of
  its own hospital (staging drops anything else).
- Collision-free IDs: primary keys embed the batch tag (window end, UTC hour),
  e.g. ENC_2026112715_0000001, so batches never overwrite earlier rows.
- Deterministic per window: the same window always produces the same data, so
  a retried run re-uploads identical files and COPY skips them.

Usage (from the repo root; reference data is read from Snowflake via .env):
    python data_generation/daily_data_generation.py --hours 3
    python data_generation/daily_data_generation.py --window-end 2026-11-27T15:00 --hours 3
The orchestrator (orchestration/isometrics_orchestration.py) calls generate_batch().
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate_data import HealthcareDataGenerator  # noqa: E402
from medical_codes_library import HOSPITAL_DISTRIBUTION  # noqa: E402
from schema import write_tables  # noqa: E402

# Transactional feeds produced per batch (and covered by the freshness SLA)
BATCH_TABLES = [
    'encounters', 'billing_transactions', 'vital_signs', 'clinical_orders', 'clinical_results',
    'medication_administration', 'quality_measures', 'care_plans', 'referrals', 'prior_authorizations',
]
IDENTIFIER = re.compile(r'^[A-Za-z_][A-Za-z0-9_$]*$')


@dataclass
class ReferenceData:
    """Existing tenants and their master data, as read from RAW_PHI."""
    hospitals: pd.DataFrame    # hospital_id, hospital_type
    patients: pd.DataFrame     # hospital_id, patient_id
    providers: pd.DataFrame    # hospital_id, provider_id
    facilities: pd.DataFrame   # hospital_id, facility_id, facility_type
    payers: pd.DataFrame       # payer_id, reimbursement_rate


def batch_tag(window_end: datetime) -> str:
    return window_end.strftime('%Y%m%d%H')


def resolve_window(hours: int, window_end: datetime | None = None) -> tuple[datetime, datetime]:
    """Window [end - hours, end), end floored to the hour, naive UTC (matches TIMESTAMP_NTZ)."""
    if window_end is None:
        window_end = datetime.now(timezone.utc).replace(tzinfo=None)
    window_end = window_end.replace(minute=0, second=0, microsecond=0)
    return window_end - timedelta(hours=hours), window_end


def seed_for(tag: str) -> int:
    return int(hashlib.sha256(tag.encode()).hexdigest()[:8], 16)


def generate_batch(ref: ReferenceData, window_start: datetime, window_end: datetime) -> dict[str, pd.DataFrame]:
    """Generate all transactional tables for one window. Pure: no I/O.

    Uses the same vectorized engine as the full generator; IDs are namespaced
    with the batch tag and the RNG is seeded from it, so the batch is unique
    and reproducible.
    """
    tag = batch_tag(window_end)
    gen = HealthcareDataGenerator(window_start, window_end, seed=seed_for(tag), verbose=False, id_namespace=tag)
    gen.load_reference(ref.patients, ref.providers, ref.facilities)

    hours = (window_end - window_start).total_seconds() / 3600
    eligible = ref.hospitals[
        ref.hospitals['hospital_type'].isin(list(HOSPITAL_DISTRIBUTION))
        & ref.hospitals['hospital_id'].isin(gen.hospital_patients.keys())
        & ref.hospitals['hospital_id'].isin(gen.hospital_providers.keys())
        & ref.hospitals['hospital_id'].isin(gen.hospital_facilities.keys())
    ].sort_values('hospital_id')
    if eligible.empty:
        return {table: pd.DataFrame() for table in BATCH_TABLES}

    # per-hospital volume: the type's daily range scaled to the window, with fractional carry
    lo = eligible['hospital_type'].map(lambda t: HOSPITAL_DISTRIBUTION[t]['daily_encounters'][0]).to_numpy()
    hi = eligible['hospital_type'].map(lambda t: HOSPITAL_DISTRIBUTION[t]['daily_encounters'][1]).to_numpy()
    expected = gen.rng.integers(lo, hi + 1) * hours / 24
    counts = np.floor(expected).astype(np.int64) + (gen.rng.random(len(expected)) < expected % 1)
    hosp = np.repeat(eligible['hospital_id'].to_numpy(dtype=object), counts)

    window_seconds = int((window_end - window_start).total_seconds())
    admissions = (np.datetime64(window_start, 's')
                  + gen.rng.integers(0, window_seconds, len(hosp)) * np.timedelta64(1, 's'))
    encounters = gen.build_encounters(hosp, admissions)
    return {'encounters': encounters, **gen.generate_encounter_children(encounters, ref.payers)}


def write_batch(batch: dict[str, pd.DataFrame], output_dir: str) -> list[str]:
    """Write one Parquet file per non-empty table, conformed to the raw DDL."""
    return write_tables(batch, output_dir)


def fetch_reference(sf, database: str) -> ReferenceData:
    """Read tenants and master data from <database>.RAW_PHI using a SnowflakeConnection."""
    if not IDENTIFIER.match(database):
        raise ValueError(f'invalid database name: {database!r}')
    raw = f'{database}.RAW_PHI'

    def frame(sql, columns):
        return pd.DataFrame(sf.execute_query(sql), columns=columns)

    return ReferenceData(
        hospitals=frame(f'select hospital_id, hospital_type from {raw}.raw_hospitals '
                        f'where coalesce(is_active, true)', ['hospital_id', 'hospital_type']),
        patients=frame(f'select hospital_id, patient_id from {raw}.raw_patients', ['hospital_id', 'patient_id']),
        providers=frame(f'select hospital_id, provider_id from {raw}.raw_providers', ['hospital_id', 'provider_id']),
        facilities=frame(f'select hospital_id, facility_id, facility_type from {raw}.raw_facilities',
                         ['hospital_id', 'facility_id', 'facility_type']),
        payers=frame(f'select payer_id, reimbursement_rate::float from {raw}.raw_payers',
                     ['payer_id', 'reimbursement_rate']),
    )


def main(argv=None):
    parser = argparse.ArgumentParser(description='Generate one window of transactional data for existing tenants')
    parser.add_argument('--hours', type=int, default=3, help='Window length in hours (default 3)')
    parser.add_argument('--window-end', type=datetime.fromisoformat, default=None,
                        help='Window end, UTC (floored to the hour); defaults to now')
    parser.add_argument('--output-dir', default='data_generation/batches',
                        help='Parent folder; files go to <output-dir>/<batch_tag>/')
    parser.add_argument('--database', default=os.getenv('DBT_RAW_DATABASE') or os.getenv('SNOWFLAKE_DATABASE'),
                        help='Database holding RAW_PHI reference data')
    args = parser.parse_args(argv)

    from utils.snowflake_connector import SnowflakeConnection

    window_start, window_end = resolve_window(args.hours, args.window_end)
    tag = batch_tag(window_end)
    sf = SnowflakeConnection()
    try:
        ref = fetch_reference(sf, args.database)
    finally:
        sf.close()

    batch = generate_batch(ref, window_start, window_end)
    paths = write_batch(batch, os.path.join(args.output_dir, tag))
    print(f'Batch {tag} [{window_start} -> {window_end}):')
    for table in BATCH_TABLES:
        print(f'  {table:<28} {len(batch[table]):>7,} rows')
    print(f'Wrote {len(paths)} files to {os.path.join(args.output_dir, tag)}')
    return 0


if __name__ == '__main__':
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
    sys.exit(main())
