"""Offline tests for the analytics API (no Snowflake connection required)."""
import datetime as dt
import hashlib
import json

import pytest
from fastapi.testclient import TestClient

from api.config import ApiClient, ConfigError, Settings, get_settings, parse_api_clients
from api.datasets import DATASETS
from api.db import QueryError
from api.main import app

HOSP1_KEY = 'imk_test_hospital_one'
AUDITOR_KEY = 'imk_test_auditor'


def sha(key: str) -> str:
    return hashlib.sha256(key.encode()).hexdigest()


class FakeRepository:
    def __init__(self, rows=None, fail=False):
        self.rows = rows if rows is not None else [{'hospital_id': 'HOSP_0001', 'metric_date': dt.date(2025, 1, 2)}]
        self.fail = fail
        self.calls = []

    def query(self, role, sql, params):
        self.calls.append((role, sql, params))
        if self.fail:
            raise QueryError('boom')
        return self.rows

    def close(self):
        pass


SETTINGS = Settings(
    snowflake_account=None, snowflake_user=None, snowflake_password=None, snowflake_warehouse=None,
    database='ISOMETRICS_TEST', marts_schema='DBT_TEST_MARTS',
    api_clients={
        sha(HOSP1_KEY): ApiClient(name='hosp-0001-dashboard', role='HOSPITAL_HOSP_0001_ANALYST'),
        sha(AUDITOR_KEY): ApiClient(name='auditor', role='HIPAA_AUDITOR'),
    },
    max_page_size=500,
)


@pytest.fixture
def repo():
    return FakeRepository()


@pytest.fixture
def client(repo):
    app.state.repository = repo
    app.dependency_overrides[get_settings] = lambda: SETTINGS
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
    del app.state.repository


def auth(key=HOSP1_KEY):
    return {'X-API-Key': key}


# --- auth -----------------------------------------------------------------

def test_health_needs_no_key(client):
    assert client.get('/health').json() == {'status': 'ok'}


@pytest.mark.parametrize('headers', [{}, {'X-API-Key': 'wrong'}])
def test_rejects_missing_or_invalid_key(client, repo, headers):
    response = client.get('/v1/datasets/clinical-quality', headers=headers)
    assert response.status_code == 401
    assert repo.calls == []


def test_me_reports_bound_role(client):
    assert client.get('/v1/me', headers=auth()).json() == {
        'client': 'hosp-0001-dashboard', 'snowflake_role': 'HOSPITAL_HOSP_0001_ANALYST'}


# --- tenant isolation -----------------------------------------------------

def test_query_runs_under_callers_role(client, repo):
    client.get('/v1/datasets/clinical-quality', headers=auth())
    client.get('/v1/datasets/clinical-quality', headers=auth(AUDITOR_KEY))
    assert [call[0] for call in repo.calls] == ['HOSPITAL_HOSP_0001_ANALYST', 'HIPAA_AUDITOR']


def test_user_input_is_bound_not_interpolated(client, repo):
    client.get('/v1/datasets/financial-performance', headers=auth(),
               params={'hospital_id': 'HOSP_0001', 'start_date': '2025-01-01', 'end_date': '2025-01-31'})
    role, sql, params = repo.calls[0]
    assert 'HOSP_0001' not in sql and '2025' not in sql
    assert params['hospital_id'] == 'HOSP_0001'
    assert params['start_date'] == dt.date(2025, 1, 1)
    assert 'from ISOMETRICS_TEST.DBT_TEST_MARTS.FCT_FINANCIAL_PERFORMANCE' in sql
    assert 'METRIC_DATE >= %(start_date)s' in sql


def test_rejects_injection_in_hospital_id(client, repo):
    response = client.get('/v1/datasets/clinical-quality', headers=auth(),
                          params={'hospital_id': "HOSP_0001' or 1=1 --"})
    assert response.status_code == 422
    assert repo.calls == []


def test_only_whitelisted_tables(client, repo):
    for name in ['fct_encounters', 'FCT_HIPAA_AUDIT_TRAIL', '..%2F..', 'raw_patients']:
        assert client.get(f'/v1/datasets/{name}', headers=auth()).status_code == 404
    assert repo.calls == []


def test_row_level_marts_are_not_exposed():
    tables = {d.table for d in DATASETS.values()}
    assert not tables & {'FCT_ENCOUNTERS', 'FCT_BILLING_TRANSACTIONS', 'FCT_HIPAA_AUDIT_TRAIL'}


# --- validation & errors --------------------------------------------------

def test_page_size_capped(client):
    assert client.get('/v1/datasets/operational', headers=auth(), params={'limit': 501}).status_code == 422
    assert client.get('/v1/datasets/operational', headers=auth(), params={'limit': 500}).status_code == 200


def test_date_filter_on_undated_dataset_rejected(client):
    response = client.get('/v1/datasets/core-measures', headers=auth(), params={'start_date': '2025-01-01'})
    assert response.status_code == 400


def test_start_after_end_rejected(client):
    response = client.get('/v1/datasets/operational', headers=auth(),
                          params={'start_date': '2025-02-01', 'end_date': '2025-01-01'})
    assert response.status_code == 400


def test_warehouse_errors_do_not_leak_details(client, repo):
    repo.fail = True
    response = client.get('/v1/datasets/operational', headers=auth())
    assert response.status_code == 503
    assert response.json() == {'detail': 'Data warehouse unavailable'}


def test_page_shape_and_json_types(client):
    body = client.get('/v1/datasets/clinical-quality', headers=auth(), params={'limit': 10, 'offset': 20}).json()
    assert body['dataset'] == 'clinical-quality'
    assert (body['count'], body['limit'], body['offset']) == (1, 10, 20)
    assert body['data'] == [{'hospital_id': 'HOSP_0001', 'metric_date': '2025-01-02'}]


def test_lists_all_datasets(client):
    names = {d['name'] for d in client.get('/v1/datasets', headers=auth()).json()}
    assert names == set(DATASETS)


# --- config ---------------------------------------------------------------

def test_api_key_config_parsing():
    entry = {sha('k'): {'name': 'svc', 'role': 'hospital_hosp_0001_analyst'}}
    clients = parse_api_clients(json.dumps(entry))
    assert clients[sha('k')].role == 'HOSPITAL_HOSP_0001_ANALYST'


@pytest.mark.parametrize('raw', [
    'not json',
    json.dumps({'plaintext-key': {'name': 'svc', 'role': 'R'}}),
    json.dumps({sha('k'): {'name': 'svc', 'role': 'R; drop table x'}}),
    json.dumps({sha('k'): {'name': 'svc'}}),
])
def test_api_key_config_rejects_bad_entries(raw):
    with pytest.raises(ConfigError):
        parse_api_clients(raw)
