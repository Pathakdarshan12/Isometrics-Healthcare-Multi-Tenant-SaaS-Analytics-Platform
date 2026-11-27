"""
IsoMetrics pipeline orchestrator: one scheduled run, end to end.

    1. resolve the batch window (default: the 3 hours ending at the current UTC hour)
    2. skip generation/load if this window's batch is already in RAW_PHI (idempotent reruns)
    3. generate the window's transactional data for existing tenants
    4. PUT the Parquet files to @RAW_PHI.HEALTHCARE_DATA_STAGE/batches/<tag>/
    5. COPY INTO each RAW_PHI table (columns and casts derived from the raw DDL)
    6. dbt: setup_rls_policies -> source freshness -> build (models, tests, snapshots)
    7. record the run in AUDIT.PIPELINE_RUN_LOG

Run from the repo root (Snowflake credentials from .env / environment):

    python -m orchestration.isometrics_orchestration --target dev
    python -m orchestration.isometrics_orchestration --target prod --hours 3
    python -m orchestration.isometrics_orchestration --target dev --skip-dbt       # load only
    python -m orchestration.isometrics_orchestration --target dev --dbt-only       # transform only

Scheduled every 3 hours by .github/workflows/pipeline_schedule.yml, which keeps
source freshness inside the 4-hour warn threshold.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))
sys.path.insert(0, str(REPO_ROOT / 'data_generation'))

from daily_data_generation import (  # noqa: E402
    BATCH_TABLES, batch_tag, fetch_reference, generate_batch, resolve_window, write_batch,
)
from schema import ddl_columns  # noqa: E402  (single DDL parser, shared with the generator)

DBT_DIR = REPO_ROOT / 'isometrics_healthcare'
IDENTIFIER = re.compile(r'^[A-Za-z_][A-Za-z0-9_$]*$')


class PipelineError(RuntimeError):
    pass


# ---------------------------------------------------------------------------
# COPY generation (from the raw DDL, so the load always matches the tables)
# ---------------------------------------------------------------------------

def _cast(name: str, col_type: str) -> str:
    if name == '_loaded_at':
        return 'CURRENT_TIMESTAMP()'
    if name == '_source_file':
        return 'METADATA$FILENAME'
    upper = col_type.upper()
    # Parquet from schema.py: DATE = date32 -> variant DATE; TIMESTAMP = int64 microseconds
    # (no logical type without USE_LOGICAL_TYPE), which ::TIMESTAMP_NTZ would read as seconds.
    if upper == 'DATE':
        return f'$1:{name}::DATE'
    if upper.startswith('TIMESTAMP'):
        return f'TO_TIMESTAMP_NTZ($1:{name}::NUMBER, 6)'
    if upper == 'TEXT':
        return f'$1:{name}::VARCHAR'
    return f'$1:{name}::{col_type}'


def build_copy_sql(table: str, database: str, stage_path: str, ddl: str | None = None) -> str:
    columns = ddl_columns(table, ddl)
    names = ', '.join(c for c, _ in columns)
    selects = ',\n        '.join(_cast(c, t) for c, t in columns)
    return (
        f'COPY INTO {database}.RAW_PHI.raw_{table} ({names})\n'
        f'FROM (\n    SELECT\n        {selects}\n'
        f'    FROM {stage_path}{table}.parquet\n)\n'
        f"FILE_FORMAT = (TYPE = PARQUET)\nON_ERROR = 'ABORT_STATEMENT'"
    )


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

def log(msg: str) -> None:
    print(f'[{datetime.utcnow():%Y-%m-%d %H:%M:%S}Z] {msg}', flush=True)


def batch_already_loaded(sf, database: str, tag: str) -> bool:
    rows = sf.execute_query(
        f'select count(*) from {database}.RAW_PHI.raw_encounters where startswith(encounter_id, %(prefix)s)',
        {'prefix': f'ENC_{tag}_'})
    return rows[0][0] > 0


def copy_batch(sf, database: str, stage_path: str, tables: list[str]) -> dict[str, int]:
    loaded = {}
    with sf.get_cursor(dict_cursor=True) as cur:
        for table in tables:
            cur.execute(build_copy_sql(table, database, stage_path))
            rows = cur.fetchall()
            loaded[table] = sum(int(r.get('rows_loaded') or 0) for r in rows if r.get('status') == 'LOADED')
            log(f'  COPY raw_{table}: {loaded[table]:,} rows')
    return loaded


def run_dbt(args: list[str], target: str) -> None:
    cmd = ['dbt', *args, '--target', target]
    log('$ ' + ' '.join(cmd))
    result = subprocess.run(cmd, cwd=DBT_DIR)
    if result.returncode != 0:
        raise PipelineError(f'{" ".join(cmd)} failed with exit code {result.returncode}')


def record_run(sf, database: str, run: dict) -> None:
    sf.execute_update(f"""
        CREATE TABLE IF NOT EXISTS {database}.AUDIT.PIPELINE_RUN_LOG (
            run_id VARCHAR(36), batch_tag VARCHAR(10), window_start TIMESTAMP_NTZ, window_end TIMESTAMP_NTZ,
            target VARCHAR(20), status VARCHAR(30), rows_loaded VARIANT,
            started_at TIMESTAMP_NTZ, finished_at TIMESTAMP_NTZ, duration_seconds NUMBER(10,1),
            error_message VARCHAR(5000), triggered_by VARCHAR(100)
        )""")
    sf.execute_update(f"""
        INSERT INTO {database}.AUDIT.PIPELINE_RUN_LOG
        SELECT %(run_id)s, %(batch_tag)s, %(window_start)s, %(window_end)s, %(target)s, %(status)s,
               PARSE_JSON(%(rows_loaded)s), %(started_at)s, %(finished_at)s, %(duration_seconds)s,
               %(error_message)s, %(triggered_by)s""", {**run, 'rows_loaded': json.dumps(run['rows_loaded'])})


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--target', default='dev', help='dbt target (dev | ci | prod)')
    parser.add_argument('--hours', type=int, default=3, help='Batch window length in hours')
    parser.add_argument('--window-end', type=datetime.fromisoformat, default=None,
                        help='Window end (UTC, floored to the hour); default now')
    parser.add_argument('--database', default=os.getenv('DBT_RAW_DATABASE') or os.getenv('SNOWFLAKE_DATABASE'),
                        help='Database with RAW_PHI (default DBT_RAW_DATABASE or SNOWFLAKE_DATABASE)')
    parser.add_argument('--skip-dbt', action='store_true', help='Generate and load only')
    parser.add_argument('--dbt-only', action='store_true', help='Skip generate/load; run dbt only')
    args = parser.parse_args(argv)

    if not args.database or not IDENTIFIER.match(args.database):
        parser.error('set --database, DBT_RAW_DATABASE or SNOWFLAKE_DATABASE to a plain identifier')
    database = args.database.upper()

    from utils.snowflake_connector import SnowflakeConnection
    from utils.upload_files_to_stage import upload_files_to_stage

    window_start, window_end = resolve_window(args.hours, args.window_end)
    tag = batch_tag(window_end)
    started = time.time()
    run = {
        'run_id': str(uuid.uuid4()), 'batch_tag': tag,
        'window_start': window_start, 'window_end': window_end, 'target': args.target,
        'status': 'RUNNING', 'rows_loaded': {}, 'started_at': datetime.utcnow(),
        'finished_at': None, 'duration_seconds': None, 'error_message': None,
        'triggered_by': os.getenv('GITHUB_EVENT_NAME', 'manual'),
    }
    log(f'Pipeline run {run["run_id"]}: batch {tag} [{window_start} -> {window_end}) target={args.target} db={database}')

    sf = SnowflakeConnection(database=database)
    try:
        if not args.dbt_only:
            if batch_already_loaded(sf, database, tag):
                log(f'Batch {tag} already loaded; skipping generate/load')
                run['status'] = 'SKIPPED_LOAD'
            else:
                log('Generating batch from current tenant reference data')
                batch = generate_batch(fetch_reference(sf, database), window_start, window_end)
                folder = Path('data_generation') / 'batches' / tag
                written = write_batch(batch, str(REPO_ROOT / folder))
                tables = [t for t in BATCH_TABLES if not batch[t].empty]
                log(f'Wrote {len(written)} files: ' + ', '.join(f'{t}={len(batch[t])}' for t in tables))

                stage = f'{database}.RAW_PHI.HEALTHCARE_DATA_STAGE'
                sf.execute_update(f'CREATE STAGE IF NOT EXISTS {stage}')
                upload_files_to_stage(str(folder), stage, subdirectory=f'batches/{tag}')
                run['rows_loaded'] = copy_batch(sf, database, f'@{stage}/batches/{tag}/', tables)

        if not args.skip_dbt:
            run_dbt(['run-operation', 'setup_rls_policies'], args.target)
            run_dbt(['source', 'freshness'], args.target)
            run_dbt(['build'], args.target)

        if run['status'] == 'RUNNING':
            run['status'] = 'SUCCESS'
        return 0
    except Exception as exc:
        run['status'] = 'FAILED'
        run['error_message'] = str(exc)[:5000]
        log(f'FAILED: {exc}')
        raise
    finally:
        run['finished_at'] = datetime.utcnow()
        run['duration_seconds'] = round(time.time() - started, 1)
        try:
            record_run(sf, database, run)
        except Exception as log_exc:  # never mask the real failure
            log(f'warning: could not write AUDIT.PIPELINE_RUN_LOG: {log_exc}')
        sf.close()
        log(f'Run {run["status"]} in {run["duration_seconds"]}s')


if __name__ == '__main__':
    sys.exit(main())
