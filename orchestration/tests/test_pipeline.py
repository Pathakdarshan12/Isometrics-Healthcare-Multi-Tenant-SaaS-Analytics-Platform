"""Offline tests for the scheduled pipeline (no Snowflake connection)."""
import os
from datetime import datetime

import pandas as pd
import pytest

from orchestration.isometrics_orchestration import build_copy_sql, ddl_columns
from daily_data_generation import (
    BATCH_TABLES, ReferenceData, batch_tag, generate_batch, resolve_window, write_batch,
)

WINDOW_END = datetime(2026, 11, 27, 15)
WINDOW = resolve_window(3, WINDOW_END)
TAG = batch_tag(WINDOW_END)

FACILITY_TYPES = ['Emergency Department', 'Medical-Surgical Unit', 'Intensive Care Unit', 'Outpatient Clinic']
PK = {
    'encounters': 'encounter_id', 'billing_transactions': 'transaction_id', 'vital_signs': 'vital_id',
    'clinical_orders': 'order_id', 'clinical_results': 'result_id', 'medication_administration': 'admin_id',
    'quality_measures': 'measure_id', 'care_plans': 'care_plan_id', 'referrals': 'referral_id',
    'prior_authorizations': 'auth_id',
}


def reference() -> ReferenceData:
    hospitals = [('HOSP_0001', 'academic_medical_center'), ('HOSP_0002', 'community_hospital'),
                 ('HOSP_0003', 'rural_hospital')]
    patients, providers, facilities = [], [], []
    for h, _ in hospitals:
        patients += [(h, f'PAT_{h}_{i:05d}') for i in range(200)]
        providers += [(h, f'PROV_{h}_{i:03d}') for i in range(20)]
        facilities += [(h, f'FAC_{h}_{i}', t) for i, t in enumerate(FACILITY_TYPES)]
    return ReferenceData(
        hospitals=pd.DataFrame(hospitals, columns=['hospital_id', 'hospital_type']),
        patients=pd.DataFrame(patients, columns=['hospital_id', 'patient_id']),
        providers=pd.DataFrame(providers, columns=['hospital_id', 'provider_id']),
        facilities=pd.DataFrame(facilities, columns=['hospital_id', 'facility_id', 'facility_type']),
        payers=pd.DataFrame([('PAY_0001', 0.85), ('PAY_0002', 0.6)], columns=['payer_id', 'reimbursement_rate']),
    )


@pytest.fixture(scope='module')
def batch():
    return generate_batch(reference(), *WINDOW)


def test_window_is_floored_to_the_hour():
    start, end = resolve_window(3, datetime(2026, 11, 27, 15, 42, 7))
    assert (start, end) == (datetime(2026, 11, 27, 12), datetime(2026, 11, 27, 15))


def test_all_tables_generated(batch):
    assert set(batch) == set(BATCH_TABLES)
    for table in ['encounters', 'billing_transactions', 'vital_signs', 'clinical_orders', 'clinical_results']:
        assert len(batch[table]) > 0, table


@pytest.mark.parametrize('table', BATCH_TABLES)
def test_columns_match_raw_ddl(batch, table):
    if batch[table].empty:
        pytest.skip(f'no {table} rows in this window')
    ddl = {c for c, _ in ddl_columns(table)}
    generated = set(batch[table].columns)
    # load-time columns are set by COPY, not the generator
    assert generated - ddl == set()
    assert ddl - generated <= {'_loaded_at', '_source_file', '_source_updated_at'}


@pytest.mark.parametrize('table', BATCH_TABLES)
def test_ids_are_unique_and_batch_scoped(batch, table):
    ids = batch[table].get(PK[table], pd.Series(dtype=str))
    assert ids.is_unique
    assert ids.str.contains(f'_{TAG}_').all()


def test_encounters_are_tenant_consistent_and_in_window(batch):
    ref, enc = reference(), batch['encounters']
    owner = lambda df, col: df.set_index(col)['hospital_id']  # noqa: E731
    assert (enc['patient_id'].map(owner(ref.patients, 'patient_id')) == enc['hospital_id']).all()
    assert (enc['provider_id'].map(owner(ref.providers, 'provider_id')) == enc['hospital_id']).all()
    assert (enc['facility_id'].map(owner(ref.facilities, 'facility_id')) == enc['hospital_id']).all()
    assert enc['admission_date'].between(WINDOW[0], WINDOW[1], inclusive='left').all()
    assert (enc['discharge_date'] >= enc['admission_date']).all()


@pytest.mark.parametrize('table', [t for t in BATCH_TABLES if t != 'encounters'])
def test_child_rows_reference_this_batch(batch, table):
    df = batch[table]
    if df.empty:
        pytest.skip(f'no {table} rows')
    enc = batch['encounters'].set_index('encounter_id')['hospital_id']
    assert df['encounter_id'].isin(enc.index).all()
    assert (df['encounter_id'].map(enc) == df['hospital_id']).all()


def test_order_foreign_keys_follow_reassigned_ids(batch):
    orders = set(batch['clinical_orders']['order_id'])
    assert set(batch['clinical_results']['order_id']) <= orders
    assert set(batch['medication_administration']['order_id']) <= orders


def test_same_window_is_deterministic():
    a = generate_batch(reference(), *WINDOW)['encounters']
    b = generate_batch(reference(), *WINDOW)['encounters']
    pd.testing.assert_frame_equal(a, b)


def test_different_windows_do_not_collide():
    other = generate_batch(reference(), *resolve_window(3, datetime(2026, 11, 27, 18)))['encounters']
    first = generate_batch(reference(), *WINDOW)['encounters']
    assert not set(other['encounter_id']) & set(first['encounter_id'])


def test_volume_scales_with_window():
    three = len(generate_batch(reference(), *resolve_window(3, WINDOW_END))['encounters'])
    day = len(generate_batch(reference(), *resolve_window(24, WINDOW_END))['encounters'])
    assert day > three * 3


def test_write_batch_skips_empty_tables_and_matches_ddl(batch, tmp_path):
    import pyarrow.parquet as pq
    from schema import arrow_schema
    paths = write_batch({'encounters': batch['encounters'], 'referrals': pd.DataFrame()}, str(tmp_path))
    assert [os.path.basename(p) for p in paths] == ['encounters.parquet']
    assert pq.read_schema(paths[0]).equals(arrow_schema('encounters'))


def test_writer_rejects_columns_missing_from_ddl(tmp_path):
    with pytest.raises(ValueError, match='not in raw DDL'):
        write_batch({'encounters': pd.DataFrame({'not_a_column': [1]})}, str(tmp_path))


@pytest.mark.parametrize('table', BATCH_TABLES)
def test_copy_sql_covers_every_ddl_column(table):
    sql = build_copy_sql(table, 'ISOMETRICS_PROD', '@ISOMETRICS_PROD.RAW_PHI.HEALTHCARE_DATA_STAGE/batches/X/')
    for column, _ in ddl_columns(table):
        assert column in sql
    assert f'FROM @ISOMETRICS_PROD.RAW_PHI.HEALTHCARE_DATA_STAGE/batches/X/{table}.parquet' in sql
    assert '_loaded_at' not in sql or 'CURRENT_TIMESTAMP()' in sql
    sqlglot = pytest.importorskip('sqlglot')
    sqlglot.parse_one(sql, read='snowflake')
