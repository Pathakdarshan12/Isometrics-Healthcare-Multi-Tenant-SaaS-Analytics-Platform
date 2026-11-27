"""Integrity tests for the streaming generator (small scale, offline)."""
import os

import numpy as np
import pandas as pd
import pyarrow.parquet as pq
import pytest

from generate_data import expected_daily_encounters, generate_dataset, main, scaled_distribution
from schema import arrow_schema

ALL_TABLES = [
    'hospitals', 'patients', 'providers', 'facilities', 'diagnoses', 'procedures', 'payers',
    'encounters', 'billing_transactions', 'vital_signs', 'clinical_orders', 'clinical_results',
    'medication_administration', 'patient_allergies', 'problem_list', 'patient_coverage', 'sdoh_screenings',
    'quality_measures', 'care_plans', 'referrals', 'prior_authorizations',
]
PK = {
    'hospitals': 'hospital_id', 'patients': 'patient_id', 'providers': 'provider_id', 'facilities': 'facility_id',
    'diagnoses': 'diagnosis_code', 'procedures': 'procedure_code', 'payers': 'payer_id',
    'encounters': 'encounter_id', 'billing_transactions': 'transaction_id', 'vital_signs': 'vital_id',
    'clinical_orders': 'order_id', 'clinical_results': 'result_id', 'medication_administration': 'admin_id',
    'patient_allergies': 'allergy_id', 'problem_list': 'problem_id', 'patient_coverage': 'coverage_id',
    'sdoh_screenings': 'screening_id', 'quality_measures': 'measure_id', 'care_plans': 'care_plan_id',
    'referrals': 'referral_id', 'prior_authorizations': 'auth_id',
}
ENCOUNTER_CHILDREN = ['billing_transactions', 'vital_signs', 'clinical_orders', 'clinical_results',
                      'medication_administration', 'quality_measures', 'care_plans', 'referrals',
                      'prior_authorizations']
PATIENT_CHILDREN = ['patient_allergies', 'problem_list', 'patient_coverage', 'sdoh_screenings']


def run(tmp_path, name, **kwargs):
    out = tmp_path / name
    params = dict(start_date='2025-01-01', end_date='2025-01-21', hospitals=6, batch_size=50_000,
                  seed=7, parquet_dir=str(out), verbose=False)
    params.update(kwargs)
    report = generate_dataset(**params)
    return out, report


def read(out, table):
    return pd.read_parquet(os.path.join(out, f'{table}.parquet'))


@pytest.fixture(scope='module')
def dataset(tmp_path_factory):
    # small batches force many patient and encounter batches, exercising the streaming path
    out, report = run(tmp_path_factory.mktemp('gen'), 'data', batch_size=2_000)
    return out, report


def test_all_tables_written_with_exact_ddl_schema(dataset):
    out, _ = dataset
    for table in ALL_TABLES:
        assert pq.read_schema(os.path.join(out, f'{table}.parquet')).equals(arrow_schema(table)), table


def test_streaming_actually_batched(dataset):
    _, report = dataset
    assert report['tables']['encounters']['batches'] > 3
    assert report['tables']['patients']['batches'] > 3


@pytest.mark.parametrize('table', ALL_TABLES)
def test_primary_keys_unique_and_present(dataset, table):
    out, _ = dataset
    ids = read(out, table)[PK[table]]
    assert len(ids) > 0, table
    assert ids.notna().all() and ids.is_unique


def owner_map(out, table, key):
    return read(out, table).set_index(key)['hospital_id']


def test_encounter_references_are_same_hospital(dataset):
    out, _ = dataset
    enc = read(out, 'encounters')
    for table, key in [('patients', 'patient_id'), ('providers', 'provider_id'), ('facilities', 'facility_id')]:
        assert (enc[key].map(owner_map(out, table, key)) == enc['hospital_id']).all(), key


@pytest.mark.parametrize('table', ENCOUNTER_CHILDREN)
def test_encounter_children_reference_existing_same_hospital_encounters(dataset, table):
    out, _ = dataset
    enc = owner_map(out, 'encounters', 'encounter_id')
    df = read(out, table)
    assert df['encounter_id'].isin(enc.index).all()
    assert (df['encounter_id'].map(enc) == df['hospital_id']).all()


@pytest.mark.parametrize('table', PATIENT_CHILDREN)
def test_patient_children_reference_same_hospital_patients(dataset, table):
    out, _ = dataset
    patients = owner_map(out, 'patients', 'patient_id')
    df = read(out, table)
    assert (df['patient_id'].map(patients) == df['hospital_id']).all()


@pytest.mark.parametrize('table,column', [
    ('medication_administration', 'witnessed_by_provider_id'),
    ('patient_allergies', 'documented_by_provider_id'),
    ('problem_list', 'documented_by_provider_id'),
])
def test_provider_references_never_cross_tenants(dataset, table, column):
    out, _ = dataset
    providers = owner_map(out, 'providers', 'provider_id')
    df = read(out, table).dropna(subset=[column])
    assert (df[column].map(providers) == df['hospital_id']).all()


def test_order_foreign_keys(dataset):
    out, _ = dataset
    orders = read(out, 'clinical_orders')
    assert read(out, 'clinical_results')['order_id'].isin(orders['order_id']).all()
    meds = orders.loc[orders['order_type'] == 'MEDICATION', 'order_id']
    assert read(out, 'medication_administration')['order_id'].isin(meds).all()


def test_billing_payers_exist(dataset):
    out, _ = dataset
    assert read(out, 'billing_transactions')['payer_id'].isin(read(out, 'payers')['payer_id']).all()


def test_readmission_flags_match_independent_recomputation(dataset):
    """Same definition as stg_healthcare__encounters: previous inpatient discharge 1-30 days earlier."""
    out, _ = dataset
    enc = read(out, 'encounters')
    ip = enc[enc['encounter_type'] == 'Inpatient'].sort_values(['patient_id', 'admission_date', 'encounter_id'])
    previous = ip.groupby('patient_id')['discharge_date'].shift()
    days = np.floor((ip['admission_date'] - previous).dt.total_seconds() / 86400)
    expected = days.between(1, 30)
    assert (ip['is_readmission'] == expected).all()
    assert not enc.loc[enc['encounter_type'] != 'Inpatient', 'is_readmission'].any()
    assert ip['is_readmission'].sum() > 0, 'dataset too small to exercise readmissions'


def test_data_quality_rules(dataset):
    out, _ = dataset
    enc = read(out, 'encounters')
    assert (enc['discharge_date'] >= enc['admission_date']).all()
    assert (enc['total_charges'] >= 0).all() and (enc['length_of_stay'] >= 0).all()
    problems = read(out, 'problem_list')
    resolved = problems['problem_status'] == 'RESOLVED'
    assert problems.loc[resolved, 'resolution_date'].notna().all()
    assert (problems.loc[resolved, 'resolution_date'] >= problems.loc[resolved, 'onset_date']).all()
    meds = read(out, 'medication_administration')
    assert meds.loc[~meds['adverse_reaction_flag'], 'reaction_description'].isna().all()
    assert meds.loc[meds['administration_status'] != 'GIVEN', 'administered_datetime'].isna().all()


def test_same_seed_is_reproducible(tmp_path):
    a, _ = run(tmp_path, 'a', hospitals=3, end_date='2025-01-03')
    b, _ = run(tmp_path, 'b', hospitals=3, end_date='2025-01-03')
    for table in ['patients', 'encounters', 'vital_signs', 'medication_administration', 'referrals']:
        pd.testing.assert_frame_equal(read(a, table), read(b, table))


def test_different_seed_differs(tmp_path):
    a, _ = run(tmp_path, 'a', hospitals=3, end_date='2025-01-03', seed=1)
    b, _ = run(tmp_path, 'b', hospitals=3, end_date='2025-01-03', seed=2)
    assert not read(a, 'encounters')['admission_date'].equals(read(b, 'encounters')['admission_date'])


def test_scaled_distribution_keeps_mix_and_total():
    dist = scaled_distribution(100)
    assert sum(c['count'] for c in dist.values()) == 100
    assert [c['count'] for c in dist.values()] == [20, 50, 30]
    assert sum(c['count'] for c in scaled_distribution(7).values()) == 7


def test_target_encounters_sizes_the_date_range(tmp_path):
    out = tmp_path / 'target'
    daily = expected_daily_encounters(scaled_distribution(2))
    main(['--hospitals', '2', '--target-encounters', str(int(daily * 3)), '--parquet-dir', str(out)])
    enc = read(out, 'encounters')
    assert enc['admission_date'].dt.normalize().nunique() == 3
    assert 0.6 * daily * 3 < len(enc) < 1.4 * daily * 3


def test_csv_output(tmp_path):
    out = tmp_path / 'csv'
    generate_dataset('2025-01-01', '2025-01-01', hospitals=1, seed=3, parquet_dir=None, csv_dir=str(out),
                     verbose=False)
    df = pd.read_csv(out / 'encounters.csv')
    assert list(df.columns) == arrow_schema('encounters').names
