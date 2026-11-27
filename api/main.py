"""IsoMetrics Healthcare analytics API.

Read-only access to aggregate mart tables. Run locally:

    uvicorn api.main:app --reload

Authentication: `X-API-Key` header. Each key maps to one Snowflake role
(see api/config.py), and queries run under that role so Snowflake's row access
policies enforce tenant isolation.
"""
from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import logging
from contextlib import asynccontextmanager
from typing import Any

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Security
from fastapi.security import APIKeyHeader
from pydantic import BaseModel

from api.config import ApiClient, Settings, get_settings
from api.datasets import DATASETS, Dataset
from api.db import QueryError, Repository, SnowflakeRepository

log = logging.getLogger(__name__)

api_key_header = APIKeyHeader(name='X-API-Key', auto_error=False)


# ---------------------------------------------------------------------------
# App + dependencies
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    if not hasattr(app.state, 'repository'):
        app.state.repository = SnowflakeRepository(get_settings())
    yield
    app.state.repository.close()


app = FastAPI(
    title='IsoMetrics Healthcare API',
    version='1.0.0',
    description='Read-only, tenant-isolated access to IsoMetrics analytics marts.',
    lifespan=lifespan,
)


def get_repository(request: Request) -> Repository:
    return request.app.state.repository


def authenticate(
    api_key: str | None = Security(api_key_header),
    settings: Settings = Depends(get_settings),
) -> ApiClient:
    if not api_key:
        raise HTTPException(status_code=401, detail='Missing X-API-Key header')
    digest = hashlib.sha256(api_key.encode('utf-8')).hexdigest()
    for key_hash, client in settings.api_clients.items():
        if hmac.compare_digest(key_hash, digest):
            return client
    raise HTTPException(status_code=401, detail='Invalid API key')


# ---------------------------------------------------------------------------
# Schemas
# ---------------------------------------------------------------------------

class DatasetInfo(BaseModel):
    name: str
    description: str
    date_filter: str | None


class ClientInfo(BaseModel):
    client: str
    snowflake_role: str


class DatasetPage(BaseModel):
    dataset: str
    count: int
    limit: int
    offset: int
    data: list[dict[str, Any]]


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get('/health', tags=['meta'])
def health() -> dict[str, str]:
    return {'status': 'ok'}


@app.get('/v1/me', response_model=ClientInfo, tags=['meta'])
def me(client: ApiClient = Depends(authenticate)) -> ClientInfo:
    return ClientInfo(client=client.name, snowflake_role=client.role)


@app.get('/v1/datasets', response_model=list[DatasetInfo], tags=['datasets'])
def list_datasets(client: ApiClient = Depends(authenticate)) -> list[DatasetInfo]:
    return [
        DatasetInfo(name=d.name, description=d.description,
                    date_filter=d.date_column.lower() if d.date_column else None)
        for d in DATASETS.values()
    ]


def build_query(dataset: Dataset, settings: Settings, hospital_id: str | None,
                start_date: dt.date | None, end_date: dt.date | None,
                limit: int, offset: int) -> tuple[str, dict[str, Any]]:
    """Build a parameterized query. Only whitelisted identifiers are interpolated."""
    sql = [f'select * from {settings.database}.{settings.marts_schema}.{dataset.table} where true']
    params: dict[str, Any] = {'limit': limit, 'offset': offset}
    if hospital_id is not None:
        sql.append('and hospital_id = %(hospital_id)s')
        params['hospital_id'] = hospital_id
    if start_date is not None:
        sql.append(f'and {dataset.date_column} >= %(start_date)s')
        params['start_date'] = start_date
    if end_date is not None:
        sql.append(f'and {dataset.date_column} <= %(end_date)s')
        params['end_date'] = end_date
    sql.append(f'order by {dataset.order_by} desc, hospital_id')
    sql.append('limit %(limit)s offset %(offset)s')
    return '\n'.join(sql), params


@app.get('/v1/datasets/{name}', response_model=DatasetPage, tags=['datasets'])
def get_dataset(
    name: str,
    hospital_id: str | None = Query(None, max_length=50, pattern=r'^[A-Za-z0-9_-]+$',
                                    description='Narrow to one hospital (row access policy still applies)'),
    start_date: dt.date | None = Query(None, description='Inclusive, on the dataset date column'),
    end_date: dt.date | None = Query(None, description='Inclusive, on the dataset date column'),
    limit: int = Query(100, ge=1),
    offset: int = Query(0, ge=0),
    client: ApiClient = Depends(authenticate),
    settings: Settings = Depends(get_settings),
    repository: Repository = Depends(get_repository),
) -> DatasetPage:
    dataset = DATASETS.get(name)
    if dataset is None:
        raise HTTPException(status_code=404, detail=f'Unknown dataset {name!r}')
    if limit > settings.max_page_size:
        raise HTTPException(status_code=422, detail=f'limit must be <= {settings.max_page_size}')
    if (start_date or end_date) and dataset.date_column is None:
        raise HTTPException(status_code=400, detail=f'Dataset {name!r} does not support date filters')
    if start_date and end_date and start_date > end_date:
        raise HTTPException(status_code=400, detail='start_date must be on or before end_date')

    sql, params = build_query(dataset, settings, hospital_id, start_date, end_date, limit, offset)
    try:
        rows = repository.query(client.role, sql, params)
    except QueryError:
        raise HTTPException(status_code=503, detail='Data warehouse unavailable')

    return DatasetPage(dataset=name, count=len(rows), limit=limit, offset=offset, data=rows)
