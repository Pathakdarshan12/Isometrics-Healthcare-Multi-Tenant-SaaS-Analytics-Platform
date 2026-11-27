"""
Raw-table schemas and a streaming writer, both derived from the Snowflake DDL.

The DDL in scripts/isometrics_healthcare_snowflake_setup.sql is the single
source of truth: the generator writes exactly those columns with matching
types, and the pipeline's COPY statements are built from the same parse. A
column added to the DDL therefore flows through generation and loading without
touching per-table code.

TableWriter appends DataFrames batch by batch (PyArrow ParquetWriter and/or
CSV in append mode), so no table ever has to be held in memory in full.
"""
from __future__ import annotations

import os
import re
import time
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

DDL_PATH = Path(__file__).resolve().parent.parent / 'scripts' / 'isometrics_healthcare_snowflake_setup.sql'
CONSTRAINT_KEYWORDS = ('PRIMARY', 'FOREIGN', 'CONSTRAINT', 'UNIQUE')
# Set by COPY at load time, never by the generator
LOAD_TIME_COLUMNS = {'_loaded_at', '_source_file'}

_ddl_cache: dict[str, str] = {}


def _ddl_text() -> str:
    if 'text' not in _ddl_cache:
        _ddl_cache['text'] = DDL_PATH.read_text(encoding='utf-8')
    return _ddl_cache['text']


def ddl_columns(table: str, ddl: str | None = None) -> list[tuple[str, str]]:
    """(column, type) pairs for raw_<table>, in DDL order."""
    ddl = ddl if ddl is not None else _ddl_text()
    match = re.search(
        rf'CREATE (?:OR REPLACE )?TABLE (?:IF NOT EXISTS )?(?:RAW_PHI\.)?raw_{table} \((.*?)\n\)[^;]*;',
        ddl, re.S | re.I)
    if not match:
        raise KeyError(f'raw_{table} not found in {DDL_PATH.name}')
    columns = []
    for line in match.group(1).splitlines():
        line = line.split('--')[0].strip().rstrip(',')
        if not line or line.split()[0].upper() in CONSTRAINT_KEYWORDS:
            continue
        parts = line.split()
        columns.append((parts[0], parts[1]))
    return columns


def arrow_type(ddl_type: str) -> pa.DataType:
    t = ddl_type.upper()
    base = t.split('(')[0]
    if base in ('VARCHAR', 'TEXT', 'STRING', 'CHAR'):
        return pa.string()
    if base == 'BOOLEAN':
        return pa.bool_()
    if base == 'DATE':
        return pa.date32()
    if base.startswith('TIMESTAMP'):
        return pa.timestamp('us')
    if base in ('INTEGER', 'INT', 'BIGINT', 'SMALLINT'):
        return pa.int64()
    if base in ('NUMBER', 'NUMERIC', 'DECIMAL'):
        scale = re.search(r',\s*(\d+)\)', t)
        return pa.float64() if scale and int(scale.group(1)) > 0 else pa.int64()
    if base in ('FLOAT', 'DOUBLE', 'REAL'):
        return pa.float64()
    raise ValueError(f'unmapped DDL type {ddl_type!r}')


def arrow_schema(table: str) -> pa.Schema:
    return pa.schema([(name, arrow_type(t)) for name, t in ddl_columns(table)])


def _datetime_values(series: pd.Series, unit: str) -> np.ndarray:
    # Already datetime64: convert in NumPy. pd.to_datetime() would run its cache
    # heuristic, which iterates the values in Python (the writer's former hotspot).
    if pd.api.types.is_datetime64_dtype(series.dtype):
        return series.to_numpy().astype(f'datetime64[{unit}]')
    # object columns of datetime.date / Timestamp / None from the row-wise generators
    return pd.to_datetime(series, cache=False).to_numpy().astype(f'datetime64[{unit}]')


def _column_to_arrow(series: pd.Series, typ: pa.DataType) -> pa.Array:
    if pa.types.is_timestamp(typ):
        return pa.array(_datetime_values(series, 'us'), type=typ, from_pandas=True)
    if pa.types.is_date32(typ):
        return pa.array(_datetime_values(series, 'D'), type=typ, from_pandas=True)
    if pa.types.is_integer(typ):
        return pa.array(pd.to_numeric(series).to_numpy(), type=typ, from_pandas=True)
    if pa.types.is_floating(typ):
        return pa.array(pd.to_numeric(series).to_numpy(dtype='float64'), type=typ, from_pandas=True)
    if pa.types.is_boolean(typ):
        return pa.array(series.to_numpy(dtype=object), type=typ, from_pandas=True)
    values = series.to_numpy(dtype=object)
    try:
        return pa.array(values, type=typ, from_pandas=True)
    except (pa.ArrowTypeError, pa.ArrowInvalid):
        # non-string values in a string column (e.g. numeric codes): stringify
        values = np.array([v if v is None or isinstance(v, str) or v != v else str(v) for v in values], dtype=object)
        return pa.array(values, type=typ, from_pandas=True)


# High-cardinality string columns (identifiers, hashes, free text): dictionary encoding
# can't compress them and costs write time, so it's enabled only for the rest.
_NO_DICTIONARY_SUFFIXES = ('_id', '_ids', '_hash', '_number', '_name', '_notes', '_text', '_description',
                           'mrn', 'npi', 'component_value', 'result_value', 'impression', 'subscriber_id')


def dictionary_columns(schema: pa.Schema) -> list[str]:
    return [f.name for f in schema
            if pa.types.is_string(f.type) and not f.name.endswith(_NO_DICTIONARY_SUFFIXES)]


def to_arrow(df: pd.DataFrame, table: str) -> pa.Table:
    """Conform a generated DataFrame to raw_<table>: DDL column order and types.

    Columns the generator doesn't produce (load-time columns) become nulls;
    unexpected extra columns raise, so schema drift is caught immediately.
    """
    schema = arrow_schema(table)
    extra = set(df.columns) - set(schema.names)
    if extra:
        raise ValueError(f'{table}: generated columns not in raw DDL: {sorted(extra)}')
    arrays = []
    for f in schema:
        if f.name in df.columns:
            arrays.append(_column_to_arrow(df[f.name], f.type))
        else:
            arrays.append(pa.nulls(len(df), type=f.type))
    return pa.Table.from_arrays(arrays, schema=schema)


@dataclass
class TableStats:
    rows: int = 0
    batches: int = 0
    write_seconds: float = 0.0
    files: list[str] = field(default_factory=list)


class TableWriter:
    """Streams batches of each raw table to <table>.parquet and/or <table>.csv."""

    def __init__(self, parquet_dir: str | None = None, csv_dir: str | None = None,
                 compression: str = 'snappy'):
        if not parquet_dir and not csv_dir:
            raise ValueError('at least one of parquet_dir / csv_dir is required')
        self.parquet_dir, self.csv_dir, self.compression = parquet_dir, csv_dir, compression
        for d in (parquet_dir, csv_dir):
            if d:
                os.makedirs(d, exist_ok=True)
        self._parquet: dict[str, pq.ParquetWriter] = {}
        self._csv_started: set[str] = set()
        self.stats: dict[str, TableStats] = {}

    def write(self, table: str, df: pd.DataFrame) -> None:
        if df is None or df.empty:
            return
        start = time.perf_counter()
        arrow = to_arrow(df, table)
        stats = self.stats.setdefault(table, TableStats())

        if self.parquet_dir:
            if table not in self._parquet:
                path = os.path.join(self.parquet_dir, f'{table}.parquet')
                self._parquet[table] = pq.ParquetWriter(path, arrow.schema, compression=self.compression,
                                                        use_dictionary=dictionary_columns(arrow.schema))
                stats.files.append(path)
            self._parquet[table].write_table(arrow)

        if self.csv_dir:
            path = os.path.join(self.csv_dir, f'{table}.csv')
            first = table not in self._csv_started
            arrow.to_pandas(date_as_object=False).to_csv(path, mode='w' if first else 'a', header=first, index=False)
            if first:
                self._csv_started.add(table)
                stats.files.append(path)

        stats.rows += arrow.num_rows
        stats.batches += 1
        stats.write_seconds += time.perf_counter() - start

    def close(self) -> None:
        for writer in self._parquet.values():
            writer.close()
        self._parquet.clear()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()


def write_tables(tables: dict[str, pd.DataFrame], parquet_dir: str) -> list[str]:
    """Write a dict of small, complete tables (e.g. one pipeline batch) to Parquet."""
    with TableWriter(parquet_dir=parquet_dir) as writer:
        for table, df in tables.items():
            writer.write(table, df)
    return [p for s in writer.stats.values() for p in s.files]


__all__ = ['DDL_PATH', 'LOAD_TIME_COLUMNS', 'TableWriter', 'arrow_schema', 'ddl_columns', 'to_arrow', 'write_tables']
