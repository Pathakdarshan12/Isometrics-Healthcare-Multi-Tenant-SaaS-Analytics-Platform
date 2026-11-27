# Row-Level Security (RLS) Implementation

Tenant isolation is enforced by **Snowflake row access policies**, not by `WHERE`
filters in dbt models. A policy is evaluated by Snowflake on every query against
the object it's attached to, whoever runs the query and however they reach it
(dbt, the dashboard, the API, a worksheet). A model never filters on
`CURRENT_ROLE()` itself. That pattern silently returns zero rows when the model is
built or queried under another role, and `assert_no_role_filters_in_models` fails
the build if anyone adds it.

```
query (any role) ──► mart table / staging view
                         │ hospital_isolation_policy ON (hospital_id)
                         ▼
             CASE on CURRENT_ROLE() / CURRENT_DATABASE()
             ├─ admin / dbt build roles in their own DB ─► all rows
             ├─ HOSPITAL_<ID>_ANALYST ─► rows where hospital_id = <ID>
             ├─ HOSPITAL_ANALYST ─► rows mapped in AUDIT.user_hospital_mapping
             └─ anything else ─► no rows (fail closed)
```

## Objects

All created per database by `dbt run-operation setup_rls_policies`
(`isometrics_healthcare/macros/setup_rls_policies.sql`):

| Object | Purpose |
|---|---|
| `<db>.RAW_PHI.HOSPITAL_ISOLATION_POLICY` | Tenant policy attached to every tenant-scoped staging view and mart table |
| `<db>.RAW_PHI.PHI_ACCESS_POLICY` | Stricter policy for raw PHI tables (`HOSPITAL_<ID>_PHI_ANALYST`, PHI admins, auditors) |
| `<db>.AUDIT.user_hospital_mapping` | Per-user, time-boxed hospital grants for the generic `HOSPITAL_ANALYST` role |

`scripts/create_rls_policies.sql` is the one-time ACCOUNTADMIN version for dev
(it also attaches `PHI_ACCESS_POLICY` to the raw tables and creates example
hospital roles).

### Mapping table

```sql
CREATE TABLE IF NOT EXISTS <db>.AUDIT.user_hospital_mapping (
    user_name VARCHAR(255),
    role_name VARCHAR(255),
    hospital_id VARCHAR(50),
    access_start_date DATE,
    access_end_date DATE,
    access_reason VARCHAR(1000),
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    created_by VARCHAR(255) DEFAULT CURRENT_USER(),
    PRIMARY KEY (user_name, role_name, hospital_id)
);
```

Only the `HOSPITAL_ANALYST` branch reads this table. Users on a hospital-specific
role (`HOSPITAL_HOSP_0001_ANALYST`) are scoped by the role name alone. One row per
(user, hospital); a user can have several rows to see several hospitals, each with
its own access window.

### Policy body

The body lives in the `rls_hospital_isolation_body()` macro:

```sql
CASE
  WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN') THEN TRUE
  WHEN CURRENT_ROLE() = 'DBT_CI_ROLE'   AND CURRENT_DATABASE() = 'ISOMETRICS_CI' THEN TRUE
  WHEN CURRENT_ROLE() = 'DBT_DEV_ROLE'  AND (CURRENT_DATABASE() = 'ISOMETRICS_DEV' OR CURRENT_DATABASE() LIKE '%_DEV') THEN TRUE
  WHEN CURRENT_ROLE() = 'DBT_PROD_ROLE' AND CURRENT_DATABASE() LIKE '%_PROD' THEN TRUE
  WHEN CURRENT_ROLE() = 'HIPAA_AUDITOR' THEN TRUE
  WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_ANALYST' AND CURRENT_ROLE() NOT LIKE '%_PHI_ANALYST' THEN
    hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_ANALYST', '\\1')
  WHEN CURRENT_ROLE() = 'HOSPITAL_ANALYST' THEN
    EXISTS (
      SELECT 1
      FROM (
        SELECT hospital_id AS mapped_hospital_id, user_name, access_start_date, access_end_date
        FROM <db>.AUDIT.user_hospital_mapping
      ) m
      WHERE m.user_name = CURRENT_USER()
        AND m.mapped_hospital_id = hospital_id
        AND CURRENT_DATE() BETWEEN m.access_start_date AND m.access_end_date
    )
  ELSE FALSE
END
```

Role naming convention: `HOSPITAL_<hospital_id>_ANALYST`, e.g. hospital
`HOSP_0001` → role `HOSPITAL_HOSP_0001_ANALYST`.

#### Why the derived table in the mapping lookup

Inside a subquery, an unqualified column name resolves to the subquery's tables
first. So the obvious

```sql
WHERE m.hospital_id = hospital_id    -- ❌ both sides are m.hospital_id
```

compares the mapping column with itself. It's always true, and any user with any
active mapping sees every hospital. The original policy in this project had
exactly this bug. Renaming the column inside a derived table
(`mapped_hospital_id`) leaves the policy argument as the only thing
`hospital_id` can refer to. The alternative is giving the policy argument a
distinct name (e.g. `row_hospital_id`). That changes the policy signature, though,
which requires detaching and recreating the policy everywhere it's attached.

### Creating vs. updating the policy

`setup_rls_policies` is idempotent and safe to run on every deploy:

1. `CREATE SCHEMA IF NOT EXISTS` for `RAW_PHI` and `AUDIT`
2. `CREATE TABLE IF NOT EXISTS` for the mapping table. It's never replaced, so
   production access grants survive deploys.
3. `CREATE ROW ACCESS POLICY IF NOT EXISTS ...`, then
   `ALTER ROW ACCESS POLICY ... SET BODY -> ...`. Body changes apply in place,
   which matters because `CREATE OR REPLACE` fails while a policy is attached.
4. On the `ci` target only, seed `DBT_CI_ROLE` mappings for `HOSP_0001` / `HOSP_0002`.

To change who can see what, edit `rls_hospital_isolation_body()` /
`rls_phi_access_body()` and rerun the operation.

## Attaching the policy: `apply_rls_policy`

Every tenant-scoped staging and mart model declares

```sql
{{ config(post_hook=["{{ apply_rls_policy() }}"]) }}
```

After the model builds, the macro:

1. skips ephemeral models (they don't exist in the warehouse)
2. looks up attached row access policies in
   `INFORMATION_SCHEMA.POLICY_REFERENCES` (real time, unlike `ACCOUNT_USAGE`)
3. if none are attached, runs `ALTER VIEW` or `ALTER TABLE` (chosen by
   materialization) `... ADD ROW ACCESS POLICY <db>.RAW_PHI.HOSPITAL_ISOLATION_POLICY ON (hospital_id)`
4. if the same policy is already attached, does nothing. This is the normal case
   for incremental tables, which persist between runs.
5. if a *different* row access policy is attached, fails the run. Snowflake
   allows only one per object.

Tables and views that dbt recreates (`CREATE OR REPLACE`) lose their policy, and
the hook re-attaches it in the same run. Reference models (`stg_reference__*`)
have no `hospital_id` and no hook.

To detach in dev:

```bash
dbt run-operation remove_rls_policy --args '{model_name: stg_healthcare__patients, object_kind: view}'
```

## Verification (all blocking in CI and prod)

| Test | Checks |
|---|---|
| `assert_rls_policy_applied` | Every staging/mart model in the dbt graph (except `staging/reference`) has `HOSPITAL_ISOLATION_POLICY` attached on `hospital_id`. It reads `INFORMATION_SCHEMA.POLICY_REFERENCES` per model, so new models are covered automatically and there's no `ACCOUNT_USAGE` lag. |
| `assert_rls_column_exists` | Every mart has a `hospital_id` column |
| `has_tenant_column` (generic) | Same, per model in YAML |
| `assert_no_cross_hospital_encounters`, `assert_no_cross_hospital_data_leakage` | Joined entities never come from different hospitals |
| `assert_no_role_filters_in_models` | No model filters on `CURRENT_ROLE()` |

```bash
dbt test --select assert_rls_policy_applied assert_rls_column_exists
dbt test --select assert_no_cross_hospital_data_leakage assert_no_cross_hospital_encounters
```

### Manual check as a tenant

```sql
USE ROLE HOSPITAL_HOSP_0001_ANALYST;
SELECT hospital_id, COUNT(*) FROM <MARTS_SCHEMA>.FCT_ENCOUNTERS GROUP BY 1;
-- exactly one row: HOSP_0001

USE ROLE HOSPITAL_ANALYST;   -- as a mapped user
SELECT DISTINCT hospital_id FROM <MARTS_SCHEMA>.FCT_ENCOUNTERS;
-- only hospitals with an active mapping row for CURRENT_USER()
```

`analyses/test_rls_isolation.sql` contains further ad-hoc checks.

## Consumers

- **Analytics API** (`api/`): each API key is bound to one Snowflake role, and
  every request runs `USE ROLE <role>` (with secondary roles disabled) before
  querying, so the policy above decides what the caller sees. The API's service
  user must be granted every role its keys map to.
- **Streamlit dashboard**: connects with the role in `.env`; it sees what that
  role sees.

## Onboarding a hospital (summary)

See [the onboarding runbook](../runbooks/%20tenant_onboarding.md) for the full
procedure. RLS-wise:

```sql
CREATE ROLE IF NOT EXISTS HOSPITAL_HOSP_0015_ANALYST;
GRANT USAGE ON DATABASE ISOMETRICS_PROD TO ROLE HOSPITAL_HOSP_0015_ANALYST;
GRANT USAGE ON SCHEMA ISOMETRICS_PROD.<MARTS_SCHEMA> TO ROLE HOSPITAL_HOSP_0015_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA ISOMETRICS_PROD.<MARTS_SCHEMA> TO ROLE HOSPITAL_HOSP_0015_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ISOMETRICS_PROD.<MARTS_SCHEMA> TO ROLE HOSPITAL_HOSP_0015_ANALYST;
GRANT ROLE HOSPITAL_HOSP_0015_ANALYST TO USER <user>;
```

No policy change is needed: the role name carries the hospital ID. See
[data_model.md](data_model.md#schema-naming) for `<MARTS_SCHEMA>`.

## Limitations

- Build roles (`DBT_*_ROLE`) see all tenants in their own database by design.
  Protect those credentials accordingly.
- Ephemeral intermediate models have no policy of their own. They're only
  reachable through the marts they're compiled into.
- `fct_cost_attribution` attributes queries by parsing `hospital_id` predicates
  from query text. Queries scoped only by this policy have no such predicate and
  are reported as `UNATTRIBUTED`.
