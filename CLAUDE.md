# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

IsoMetrics Healthcare is a multi-tenant healthcare analytics platform on **Snowflake + dbt**. Each hospital (`hospital_id`) is a tenant; tenant isolation via Snowflake row access policies (RLS) is the central design constraint. Data is synthetic (generated in Python), loaded to a Snowflake stage and into `RAW_PHI`, transformed by dbt, and surfaced in a Streamlit dashboard and a read-only FastAPI service (`api/`).

## Commands

All dbt commands run from `isometrics_healthcare/` and need a `~/.dbt/profiles.yml` with profile `isometrics_healthcare` (not committed; see `.github/workflows/dbt_ci.yml` for the expected shape). Python tooling reads Snowflake creds from a root `.env` (`SNOWFLAKE_USER/PASSWORD/ACCOUNT/WAREHOUSE/DATABASE/SCHEMA/ROLE`).

```bash
# Setup (Windows venv lives at ./venv)
pip install -r requirements.txt          # keep UTF-8: don't regenerate with PowerShell `>` (writes UTF-16)
cd isometrics_healthcare && dbt deps

# Build by layer (mirrors CI order)
dbt run --select staging
dbt run --select intermediate             # ephemeral — compiles into downstream models
dbt run --select marts
dbt run --select fct_encounters --full-refresh
dbt snapshot

# Tests
dbt test --exclude assert_rls_column_exists assert_rls_policy_applied
dbt test --select assert_no_cross_hospital_encounters     # single singular test
dbt test --select stg_healthcare__encounters              # all tests on one model

# RLS setup (idempotent; creates/updates policies + AUDIT.user_hospital_mapping in target DB)
dbt run-operation setup_rls_policies
dbt run-operation remove_rls_policy --args '{model_name: stg_healthcare__patients, object_kind: view}'

# Lint (sqlfluff + dbt templater are in requirements; no .sqlfluff config yet)
sqlfluff lint models/

# Docs
dbt docs generate && dbt docs serve
```

Data pipeline (from repo root):
```bash
python data_generation/generate_data.py                       # 100 hospitals, 30 days -> data_generation/parquet/*.parquet
python data_generation/generate_data.py --target-encounters 3000000   # size the date range for ~3M encounters
python data_generation/generate_data.py --hospitals 10 --days 7 --format both  # small run, Parquet + CSV
python -m pytest data_generation/tests                        # generator integrity tests (offline)
python -m utils.upload_files_to_stage                         # PUT to @RAW_PHI.HEALTHCARE_DATA_STAGE/2023/
snowsql -f scripts/load_data_to_snowflake.sql                 # COPY INTO all 21 raw tables
streamlit run monitoring_dashboard/app.py
```

Scheduled pipeline (from repo root; `.github/workflows/pipeline_schedule.yml` runs it every 3h on prod when repo variable `PIPELINE_ENABLED=true`):
```bash
python -m orchestration.isometrics_orchestration --target dev [--hours 3] [--skip-dbt | --dbt-only]
python -m pytest orchestration/tests                          # offline
```

API (from repo root):
```bash
pip install -r api/requirements.txt
python -m pytest api/tests                                    # offline; fake repository, no Snowflake
python -m pytest api/tests/test_api.py::test_query_runs_under_callers_role   # single test
python -m api.keys <client-name> <SNOWFLAKE_ROLE>             # new key -> ISOMETRICS_API_KEYS entry
uvicorn api.main:app --reload
```

When the warehouse is unavailable, `dbt parse` still validates Jinja/YAML offline; `dbt compile` needs a live connection.

One-time Snowflake bootstrap scripts live in `scripts/` (`isometrics_healthcare_snowflake_setup.sql` → databases/roles/warehouses, `create_rls_policies.sql`, `load_data_to_snowflake.sql`, `metadata_driven_stage_to_raw.sql`).

## Architecture

### Environments
Three databases — `ISOMETRICS_DEV`, `ISOMETRICS_CI`, `ISOMETRICS_PROD` — each built by its own role (`DBT_DEV_ROLE`, `DBT_CI_ROLE`, `DBT_PROD_ROLE`). The RLS policies in `macros/setup_rls_policies.sql` grant visibility by `CURRENT_ROLE()` + `CURRENT_DATABASE()` combos, so **behavior differs by role/env**; always consider which role a model is built and queried under.

Sources (`models/staging/*/_*__sources.yml`) read `RAW_PHI` in `env_var('DBT_RAW_DATABASE', target.database)`. CI sets `DBT_RAW_DATABASE=ISOMETRICS_DEV` because CI's own `RAW_PHI` is dropped after each run; prod reads `ISOMETRICS_PROD.RAW_PHI`.

### Ingestion (outside dbt)
Two load paths into `RAW_PHI.raw_*`: `scripts/load_data_to_snowflake.sql` (explicit `COPY INTO` with casts for all 21 tables; the one the README Quick Start uses) and `scripts/metadata_driven_stage_to_raw.sql` (`SOURCE_FILE_CONFIG` + `SP_LOAD_RAW_TABLE` / `SP_LOAD_ALL_RAW_TABLES`, currently configured for 9 sources). Adding a raw source means: DDL in `isometrics_healthcare_snowflake_setup.sql`, a generator method + `main()` call in `data_generation/generate_data.py`, the file in `utils/csv_to_parquet.py`, a `COPY` block, and a dbt source entry. Generator output columns must match the raw DDL exactly. `orchestration/isometrics_orchestration.py` is only a commented outline of the intended sequence (generate → stage → SP → dbt run/test/snapshot/docs); there is no working orchestrator.

### dbt layers (`isometrics_healthcare/models/`)
- **staging** (`stg_healthcare__*`, `stg_reference__*`) — views, mostly `secure=True`. This is where de-identification happens (names/MRN dropped, 3-digit ZIP via `deidentify_zipcode`, age bands) and where **business logic that other layers depend on is computed**, notably `stg_healthcare__encounters`: it enforces that patient/provider/facility share the encounter's `hospital_id` (mismatches are dropped) and derives `is_readmission` with `lag()` over `(patient_id, hospital_id)`.
- **intermediate** (`int_*`) — ephemeral; joins/enrichment (`int_encounters__enriched`, patient profile, med safety, revenue cycle…).
- **marts** — tables (some incremental) grouped into `core`, `clinical`, `financial`, `operational`, `observability`. Observability marts (`fct_cost_attribution`, `fct_hipaa_audit_trail`, `fct_sla_monitoring`) read `snowflake.account_usage.*`, so they need account-usage privileges and reflect whatever DB they run in.
- **snapshots** — SCD2 on hospitals, providers, facilities.

Layer defaults (materialization, schema, tags, `meta.sla_hours`) are set in `dbt_project.yml`; tests use `+store_failures: true` into `test_failures`.

### Tenant isolation conventions (follow these when adding models)
- Access control lives only in row access policies, never in `WHERE CURRENT_ROLE() ...` filters inside models (those silently empty CI/prod builds).
- Every model must carry `hospital_id`; generic test `has_tenant_column` and singular `assert_rls_column_exists` enforce this.
- Staging and mart models attach RLS with `post_hook=["{{ apply_rls_policy() }}"]`. The macro checks `INFORMATION_SCHEMA.POLICY_REFERENCES`, skips if already attached (incremental tables persist), uses `ALTER VIEW` vs `ALTER TABLE` by materialization, and errors if a different policy is attached. The policy must exist first (`setup_rls_policies`).
- `assert_rls_policy_applied` and `assert_rls_column_exists` build their check lists from the dbt graph (all staging/marts models except `staging/reference`), so new models are covered automatically. Never hard-code schema names in tests: dbt builds into `<target schema>_<layer>` (e.g. `DBT_DEV_MARTS`).
- Policy bodies are in `rls_hospital_isolation_body()` / `rls_phi_access_body()` in `macros/setup_rls_policies.sql`; `setup_rls_policies` creates-if-missing then `ALTER ... SET BODY`, so edit the body there and rerun. In a policy subquery, never compare `table.hospital_id = hospital_id` — the unqualified name binds to the table column, not the policy argument (see the derived-table pattern used there).
- Joins and window partitions across tenant-scoped entities must include `hospital_id`; `no_cross_tenant_leakage` (generic) and `assert_no_cross_hospital_*` (singular) check this.
- Flag PHI with `meta: {contains_phi: true, phi_fields: [...]}`; use `no_phi_in_column` on free-text columns. Staging applies HIPAA Safe Harbor: birth year only, ages top-coded at 90, `deidentify_zipcode` (3 digits, restricted prefixes → `000`).

### Macros
Clinical scoring macros (`calculate_apache_ii_score`, `calculate_sofa_score`, `calculate_qsofa_score`, `calculate_mews_score`, `calculate_news2_score`, `calculate_cha2ds2_vasc_score`, `calculate_hasbled_score`, `charlson_condition`/`charlson_weight`) and utilities (`safe_divide`, `calculate_percentage`, `tenant_surrogate_key`, `calculate_age_group`, `calculate_length_of_stay`, `calculate_ar_aging_bucket`) emit SQL expressions to inline in selects. RLS macros: `setup_rls_policies`, `apply_rls_policy`, `remove_rls_policy`, `verify_rls_policy`.

Write macro docstrings as Jinja comments (`{# #}`), never SQL `/* */`: Jinja renders inside SQL comments, so a usage example like `{{ my_macro(...) }}` in a `/* */` docstring makes the macro call itself forever.

### CI/CD
- `.github/workflows/dbt_ci.yml` — on push/PR to `main`: writes profile from secrets, bootstraps schemas via SnowSQL, `setup_rls_policies`, runs staging → intermediate → marts, then all tests, RLS verification and isolation tests (all blocking), and drops the CI schemas.
- `.github/workflows/dbt_prod.yml` — `workflow_run` after "dbt CI" succeeds on `main` (or manual dispatch with optional full refresh); checks out the exact SHA CI tested and deploys to `ISOMETRICS_PROD`.
- `.github/workflows/api_ci.yml` — runs `api/tests` on changes under `api/`.
- Singular tests are selected by name (`dbt test --select assert_x`); `test_name:` only matches generic tests.

### Dashboard and API
`monitoring_dashboard/app.py` (Streamlit, multi-page with `pages/`) queries mart tables directly via `snowflake.connector` using `.env` creds (tables hard-coded to `DBT_DEV_MARTS`); the role in `.env` determines what RLS lets it see.

`api/` (FastAPI) never filters tenants itself: each API key (stored as a SHA-256 digest in `ISOMETRICS_API_KEYS`) is bound to one Snowflake role, and `api/db.py` runs `USE ROLE` for it per request with secondary roles disabled, so the row access policy decides visibility. Only datasets in `api/datasets.py` (aggregate marts) are queryable; table names come from that whitelist and all user input is bound as parameters. Tests inject a fake repository via `app.state.repository` and override `get_settings`.

## Docs

`docs/architecture/` (data model, RLS, incremental strategy, ingestion) and `docs/runbooks/` describe the system as built. Update them when changing RLS, materializations, load paths or schema naming. `docs/blog.md` is a personal article, not reference documentation.

## Known pitfalls
- Readmissions are defined in `stg_healthcare__encounters` (previous *inpatient* stay at the same hospital, 1–30 days); `assert_readmission_logic_valid` recomputes this independently with a self-join, so change both together.
- Data generation (`data_generation/generate_data.py`) is a vectorized, streaming engine: patients and encounters are produced in batches (`--batch-size`), each batch's dependent tables are generated and written immediately via `schema.TableWriter`, then released. Keep new table logic vectorized (NumPy arrays, `expand()` for per-parent child counts) and take randomness from `self.rng` so a seed reproduces the dataset. Tenant references must come from `GroupSampler`s keyed by hospital (`self._sampler('providers')` etc.), never from a global ID range.
- `data_generation/schema.py` derives Arrow schemas and the pipeline's COPY columns from the raw DDL; the writer raises on generated columns missing from the DDL. Add a column to the DDL first.
- The scheduled batch generator (`daily_data_generation.py`) reuses the same engine with `id_namespace=<batch tag>` (IDs like `ENC_<YYYYMMDDHH>_0000001`) and a seed derived from the tag; keep both when adding a feed, or reruns duplicate rows and batches overwrite each other.
- Source freshness is configured at source level and disabled (`freshness: null`) for master-data tables; a new transactional feed must be added to `BATCH_TABLES` or it will breach the freshness SLA.
