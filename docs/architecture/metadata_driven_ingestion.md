# Ingestion: Stage → RAW_PHI

Synthetic data goes through generate → CSV → Parquet → Snowflake stage → `RAW_PHI`
raw tables. There are two ways to do the last step:

| Path | File | Covers | Use for |
|---|---|---|---|
| Explicit `COPY INTO` | `scripts/load_data_to_snowflake.sql` | all 21 raw tables | Quick start, full loads |
| Metadata-driven procedures | `scripts/metadata_driven_stage_to_raw.sql` | 9 sources configured (hospitals, patients, providers, facilities, diagnoses, procedures, payers, encounters, billing) | Config-driven batch/incremental loads with run logging |

## End-to-end (from the repo root)

```bash
python data_generation/generate_data.py     # CSVs -> data_generation/2025/
python utils/csv_to_parquet.py              # -> data_generation/parquet/
python -m utils.upload_files_to_stage       # PUT -> @RAW_PHI.HEALTHCARE_DATA_STAGE/2023/
snowsql -f scripts/load_data_to_snowflake.sql
```

`upload_files_to_stage` reads credentials from `.env` and takes `--folder`,
`--stage`, `--subdirectory` and `--pattern`. It exits non-zero if any file fails to
upload.

## Explicit COPY path

Each raw table has one `COPY INTO ... FROM (SELECT $1:col::TYPE ...)` block reading
`@healthcare_data_stage/2023/<table>.parquet`, with `ON_ERROR = 'ABORT_STATEMENT'`.
Casts are explicit because the Parquet files come from CSV, so dates and
timestamps arrive as strings. DATE columns are cast through `TIMESTAMP_NTZ` to
tolerate a time part. `_loaded_at` is set to `CURRENT_TIMESTAMP()` at load.

## Metadata-driven path

Configuration lives in `RAW_PHI` tables, so adding or changing a source is a data
change, not a code change:

| Table | Answers |
|---|---|
| `FILE_FORMAT_MASTER` | How to parse a file (type, compression, encoding, format options) |
| `SOURCE_FILE_CONFIG` | What arrives where: stage path, file pattern, ingestion type (`BATCH` / `INCREMENTAL` / `STREAM`), schedule, active flag |
| `DATA_FIELD_MASTER` | Canonical business fields: type, length/precision, PII flag, domain |
| `FILE_COLUMN_MAPPING` | File column → business field, position, PK flag, `transformation_rule`, `default_value`, `validation_rule` |
| `RAW_TABLE_MAPPING` | Where it lands: raw table, error table, load type (`APPEND` / `MERGE` / `FULL_REFRESH`), PK / merge keys, clustering |
| `BATCH_RUN_LOG` | One row per run: status, rows read/inserted/updated/errored, files, duration, error |
| `FILE_PROCESS_LOG` | One row per file processed |

### `SP_LOAD_RAW_TABLE(source_id, batch_run_date)`

1. Read the source's config, file format and raw-table mapping
2. Insert a `STARTED` row in `BATCH_RUN_LOG`
3. Build the column list and `SELECT` clause from `FILE_COLUMN_MAPPING`
   (applying `transformation_rule`, e.g. `CURRENT_TIMESTAMP()` or `METADATA$FILENAME`)
4. Create a temporary staging table and a temporary file format
5. `COPY INTO` the temp table from `landing_path` + `file_pattern`
6. Apply the load type: `FULL_REFRESH` (truncate + insert), `APPEND` (insert), or
   `MERGE` on `merge_key_fields`
7. Apply clustering if configured
8. Update `BATCH_RUN_LOG` with counts and status. Drop temp objects. On error,
   mark the batch `FAILED` and return the error.

### `SP_LOAD_ALL_RAW_TABLES(batch_run_date)`

Loops over active `SOURCE_FILE_CONFIG` rows in `source_id` order, calls
`SP_LOAD_RAW_TABLE` for each, and returns `COMPLETED: Success=<n>, Failed=<n>`.

```sql
CALL RAW_PHI.SP_LOAD_RAW_TABLE(8);              -- encounters
CALL RAW_PHI.SP_LOAD_ALL_RAW_TABLES(CURRENT_DATE());

SELECT * FROM RAW_PHI.BATCH_RUN_LOG ORDER BY batch_run_timestamp DESC LIMIT 20;
```

Note: the script is written for `ISOMETRICS_DEV` (e.g. the `FILE_LOG_ID` sequence
is created as `ISOMETRICS_DEV.RAW_PHI.FILE_LOG_ID`) and recreates its config
tables with `CREATE OR REPLACE`. Rerunning the whole script resets the
configuration and run history.

## Adding a raw source

1. **DDL**: add `CREATE TABLE raw_<name>` to `scripts/isometrics_healthcare_snowflake_setup.sql`
   (include `hospital_id` if it's tenant-scoped, and `_loaded_at`).
2. **Data**: add a generator method and a `main()` call in
   `data_generation/generate_data.py`, and the CSV name in `utils/csv_to_parquet.py`.
   Generated columns must match the DDL exactly.
3. **Load**: add a `COPY INTO` block to `scripts/load_data_to_snowflake.sql`, and/or
   `SOURCE_FILE_CONFIG` / `FILE_COLUMN_MAPPING` / `RAW_TABLE_MAPPING` rows for the
   procedure path.
4. **dbt**: add the table to `models/staging/healthcare/_healthcare__sources.yml`,
   create `stg_healthcare__<name>.sql` with the `apply_rls_policy()` post-hook, and
   document and test it in `_healthcare__models.yml`.

`assert_rls_policy_applied` will fail until the new staging model has the policy
attached, which is the intended safety net.
