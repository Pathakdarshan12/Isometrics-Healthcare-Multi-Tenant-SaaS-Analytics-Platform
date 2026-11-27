# Snowflake setup (new account)

End-to-end setup of a fresh Snowflake account: bootstrap, key-pair auth, dev data
load, dbt build, RLS, production seed, GitHub Actions, and the scheduled pipeline.
Plan on about an hour, most of it waiting for data generation and loads.

Run SQL as **ACCOUNTADMIN** in a Snowsight worksheet: open the file, paste it in,
and use **Run All** (Ctrl+Shift+Enter). Run shell commands from the repo root in
Git Bash, or in PowerShell where noted.

## Requirement: Enterprise Edition

Tenant isolation is built on row access policies, which need **Enterprise Edition
or higher**. On Standard Edition, any statement involving them fails with
`Unsupported feature`. Check under Snowsight → *Admin* → *Accounts* → *Edition*. A
free trial lets you choose the edition at sign-up: pick Enterprise (or Business
Critical).

## What gets created

| Object | Dev | CI | Prod |
|---|---|---|---|
| Database | `ISOMETRICS_DEV` | `ISOMETRICS_CI` | `ISOMETRICS_PROD` |
| Role | `DBT_DEV_ROLE` | `DBT_CI_ROLE` | `DBT_PROD_ROLE` |
| Warehouse | `DBT_DEV_WH` (XS) | `DBT_CI_WH` (XS) | `DBT_PROD_WH` (S) |
| Service user | `DBT_USER` | `DBT_USER` | `DBT_PROD_USER` |
| Raw data | `RAW_PHI` (21 tables, stage) | reads dev `RAW_PHI` | `RAW_PHI` (21 tables, stage) |
| dbt schemas | `DBT_DEV_STAGING`, `DBT_DEV_MARTS` | `DBT_CI_<run>_*` (dropped per run) | `DBT_PROD_STAGING`, `DBT_PROD_MARTS` |

The service users have no password. Snowflake no longer allows password-only
sign-in for new users, so they are `TYPE = SERVICE` and authenticate with an RSA key
pair. Every client supports this: dbt, the Python utilities, the pipeline, the API,
the dashboard and GitHub Actions.

---

## 1. Bootstrap the account

Run [`scripts/isometrics_healthcare_snowflake_setup.sql`](../../scripts/isometrics_healthcare_snowflake_setup.sql)
as ACCOUNTADMIN. It is idempotent and never drops data, so you can safely rerun it.

Check that the final `SHOW TABLES` statements list 21 tables in each of
`ISOMETRICS_DEV.RAW_PHI` and `ISOMETRICS_PROD.RAW_PHI`.

Find your **account identifier**: Snowsight → your name (bottom left) → *Account* →
*View account details* → **Account identifier**, in the form `ORGNAME-ACCOUNTNAME`.
dbt, `.env` and the GitHub secrets all use this value.

## 2. Create key pairs for the service users

Run this in Git Bash (OpenSSL ships with Git for Windows):

```bash
mkdir -p ~/.snowflake && cd ~/.snowflake
for u in dbt_user dbt_prod_user; do
  openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out $u.p8 -nocrypt
  openssl rsa -in $u.p8 -pubout -out $u.pub
  echo "== $u public key (paste into ALTER USER):"
  grep -v "PUBLIC KEY" $u.pub | tr -d '\n'; echo
done
```

Then, in Snowsight:

```sql
USE ROLE ACCOUNTADMIN;
ALTER USER DBT_USER      SET RSA_PUBLIC_KEY = '<dbt_user public key body>';
ALTER USER DBT_PROD_USER SET RSA_PUBLIC_KEY = '<dbt_prod_user public key body>';
DESC USER DBT_USER;   -- RSA_PUBLIC_KEY_FP is now filled in
```

Keep the `.p8` private keys out of the repo. `~/.snowflake/` is outside it.

## 3. Configure dbt and `.env`

`~/.dbt/profiles.yml` (on Windows: `C:\Users\<you>\.dbt\profiles.yml`):

```yaml
isometrics_healthcare:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: ORGNAME-ACCOUNTNAME
      user: DBT_USER
      private_key_path: C:/Users/<you>/.snowflake/dbt_user.p8
      role: DBT_DEV_ROLE
      database: ISOMETRICS_DEV
      warehouse: DBT_DEV_WH
      schema: DBT_DEV          # layers build into DBT_DEV_STAGING / DBT_DEV_MARTS
      threads: 4
```

Use `schema: DBT_DEV`, not `DBT_DEV_STAGING`. dbt appends the layer name, and both
the dashboard and the API read `DBT_DEV_MARTS`.

Repo-root `.env`, used by the upload script, pipeline, API and dashboard:

```bash
SNOWFLAKE_ACCOUNT=ORGNAME-ACCOUNTNAME
SNOWFLAKE_USER=DBT_USER
SNOWFLAKE_PRIVATE_KEY_PATH=C:/Users/<you>/.snowflake/dbt_user.p8
SNOWFLAKE_ROLE=DBT_DEV_ROLE
SNOWFLAKE_WAREHOUSE=DBT_DEV_WH
SNOWFLAKE_DATABASE=ISOMETRICS_DEV
SNOWFLAKE_SCHEMA=RAW_PHI
ISOMETRICS_MARTS_SCHEMA=DBT_DEV_MARTS
```

(`SNOWFLAKE_PASSWORD` still works as a fallback when no key path is set, for
accounts that allow it.)

Verify the connection:

```bash
pip install -r requirements.txt
cd isometrics_healthcare && dbt deps && dbt debug && cd ..   # "All checks passed!"
```

## 4. Generate and load dev data

```bash
# Size is driven mostly by --hospitals: each hospital has a fixed patient panel
# (~12k patients) with allergies, problems, coverage and SDOH rows, whatever the date range.
python data_generation/generate_data.py --hospitals 3 --days 7      # ~270k rows, 2.8k encounters (small dev set)
# --hospitals 5  --days 30  -> ~0.9M rows, 20k encounters
# --hospitals 10 --days 30  -> ~2.0M rows, 38k encounters
# 100 hospitals (the default) is ~6M rows for a single day, because of the patient panels
# or the full-size dataset (~3M encounters, ~104M rows, ~5 minutes, ~3.8 GB):
# python data_generation/generate_data.py --target-encounters 3000000

python -m utils.upload_files_to_stage            # PUT to @RAW_PHI.HEALTHCARE_DATA_STAGE/2023/
```

Then run [`scripts/load_data_to_snowflake.sql`](../../scripts/load_data_to_snowflake.sql)
in Snowsight. `LIST` near the top should show 21 files, and the row-count queries at
the end should be non-zero.

Start with the default size. The 3M-encounter load takes noticeably longer on an XS
warehouse.

## 5. Build with dbt

```bash
cd isometrics_healthcare
dbt run-operation setup_rls_policies   # policies + AUDIT.user_hospital_mapping in ISOMETRICS_DEV
dbt run                                # staging -> intermediate -> marts
dbt snapshot
dbt test                               # some severity=warn tests may warn; errors should be 0
cd ..
```

The observability marts (`fct_cost_attribution`, `fct_hipaa_audit_trail`,
`fct_sla_monitoring`) read `SNOWFLAKE.ACCOUNT_USAGE`, which lags by up to about 2 hours
and is nearly empty on a brand-new account. Expect few rows there at first.

## 6. Raw-table RLS and analyst roles

Run [`scripts/create_rls_policies.sql`](../../scripts/create_rls_policies.sql)
in Snowsight. It:

- attaches the dbt-managed policies to the 18 tenant-scoped raw tables. Databases
  whose policies don't exist yet, which is prod at this point, are skipped and listed
  in the result.
- creates `HOSPITAL_HOSP_0001_ANALYST`, `HOSPITAL_HOSP_0002_ANALYST`,
  `HOSPITAL_ANALYST` and `HIPAA_AUDITOR`, and grants them read access on
  `DBT_DEV_MARTS`.
- runs an isolation check at the end. ACCOUNTADMIN sees every hospital; the
  `HOSP_0001` analyst sees only `HOSP_0001`.

## 7. Seed production raw data

Run [`scripts/seed_prod_from_dev.sql`](../../scripts/seed_prod_from_dev.sql).
It copies every dev raw table into an *empty* prod table and skips tables that
already have rows, so it never overwrites pipeline batches.

## 8. GitHub Actions

Repo → *Settings* → *Secrets and variables* → *Actions* → **Secrets**:

| Secret | Value |
|---|---|
| `SNOWFLAKE_ACCOUNT` | `ORGNAME-ACCOUNTNAME` |
| `SNOWFLAKE_USER` | `DBT_USER` |
| `SNOWFLAKE_PRIVATE_KEY` | full contents of `~/.snowflake/dbt_user.p8`, including the `BEGIN`/`END` lines |
| `SNOWFLAKE_PROD_USER` | `DBT_PROD_USER` |
| `SNOWFLAKE_PROD_PRIVATE_KEY` | full contents of `~/.snowflake/dbt_prod_user.p8` |
| `SLACK_WEBHOOK_URL` | optional; the Slack steps are skipped without it |

Remove the old `SNOWFLAKE_PASSWORD` / `SNOWFLAKE_PROD_PASSWORD` secrets if they are
still there; nothing reads them any more. The `production` environment used by the
prod workflows is created automatically on first run. Add required reviewers to it
if you want a manual approval gate.

Then:

1. Push to `main`, or open a PR. **dbt CI** builds into `ISOMETRICS_CI.DBT_CI_<run>_*`,
   runs every test, and drops those schemas.
2. When CI passes on `main`, **dbt Production Deployment** runs. You can also start it
   from *Actions* → *Run workflow*. It builds `DBT_PROD_STAGING` / `DBT_PROD_MARTS`
   and runs snapshots and tests.
3. Run `scripts/create_rls_policies.sql` **again**. Prod's policies exist now, so the
   prod raw tables get attached too.

## 9. Scheduled pipeline

1. *Actions* → **Scheduled pipeline** → *Run workflow* once by hand. It generates the
   last 3-hour batch, PUTs it to `ISOMETRICS_PROD.RAW_PHI.HEALTHCARE_DATA_STAGE/batches/<tag>/`,
   COPYs it in, runs dbt, and logs to `ISOMETRICS_PROD.AUDIT.PIPELINE_RUN_LOG`.
2. When it succeeds, set the repository **variable** `PIPELINE_ENABLED` = `true`
   (*Settings* → *Secrets and variables* → *Actions* → *Variables*). It then runs
   every 3 hours.

This pipeline is the main ongoing cost: 8 runs a day on a Small warehouse. Check
*Admin* → *Cost Management* after a day, and set `PIPELINE_ENABLED=false` to pause it.

```sql
SELECT * FROM ISOMETRICS_PROD.AUDIT.PIPELINE_RUN_LOG ORDER BY started_at DESC LIMIT 10;
```

## 10. API and dashboard (dev)

```bash
pip install -r api/requirements.txt
python -m api.keys hosp-0001-dashboard HOSPITAL_HOSP_0001_ANALYST   # add the printed entry to ISOMETRICS_API_KEYS in .env
uvicorn api.main:app --reload
streamlit run monitoring_dashboard/app.py
```

`DBT_USER` was granted the analyst roles in step 6, so the API can switch to them.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `JWT token is invalid` | Public key not set or mismatched (`DESC USER`), wrong account identifier, or the profile points at the wrong `.p8`. |
| `Insufficient privileges to operate on schema 'RAW_PHI'` in `setup_rls_policies` | The bootstrap script hasn't run, or was run in another account. Rerun it. |
| `Database 'SNOWFLAKE' does not exist or not authorized` | `GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE` (bootstrap section 2) is missing for that role. |
| Upload fails: stage does not exist | Run the bootstrap first; it creates `RAW_PHI.HEALTHCARE_DATA_STAGE`. |
| `COPY` loads 0 rows | Those files were already loaded (COPY remembers them for 64 days). After regenerating, `TRUNCATE` the raw tables, then upload and load again. |
| Marts are empty when queried as an analyst | Expected for any hospital other than the one in the role name. As ACCOUNTADMIN or `DBT_DEV_ROLE` you should see all of them. |
| CI fails reading sources | `DBT_CI_ROLE` needs `SELECT` on `ISOMETRICS_DEV.RAW_PHI` (bootstrap section 8), and dev data must be loaded. |
| Policy already attached / `ALTER ... ADD ROW ACCESS POLICY` errors in step 6 | Reported and skipped by design; the result lists them. |
