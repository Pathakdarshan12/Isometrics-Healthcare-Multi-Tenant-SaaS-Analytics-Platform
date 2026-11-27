# Tenant Offboarding

## Scenario
**Hospital:** Metro General (`HOSP_0003`) ends its contract. The Business Associate
Agreement requires that its PHI be returned or destroyed within 30 days of
termination, with evidence of destruction.

> **Conventions.** `MARTS` / `STAGING` mean the dbt schemas for the target (prod:
> `MARTS_MARTS` / `MARTS_STAGING`); see
> [data_model.md](../architecture/data_model.md#schema-naming).

Offboarding has three stages: **revoke access immediately**, **export data if the
contract requires it**, then **destroy the data** after the retention window.
The order matters: access is cut before anything else, so nothing can be read
during the wind-down.

---

## Phase 1: Revoke Access (Day 0)

```sql
USE ROLE ACCOUNTADMIN;
USE DATABASE ISOMETRICS_PROD;

-- 1. Disable the hospital's users
SHOW USERS LIKE '%metro%';                       -- find them
ALTER USER metro_analyst SET DISABLED = TRUE;

-- 2. Remove the hospital-specific role(s). The row access policy scopes
--    HOSPITAL_HOSP_0003_ANALYST by name, so without the role there's no path to the data.
REVOKE ROLE HOSPITAL_HOSP_0003_ANALYST FROM USER metro_analyst;
DROP ROLE IF EXISTS HOSPITAL_HOSP_0003_ANALYST;
DROP ROLE IF EXISTS HOSPITAL_HOSP_0003_PHI_ANALYST;

-- 3. End mapping-table access for HOSPITAL_ANALYST users. Rows are end-dated,
--    not deleted, so the grant history stays auditable.
UPDATE AUDIT.user_hospital_mapping
SET access_end_date = CURRENT_DATE() - 1,
    access_reason = access_reason || ' | Revoked: contract terminated ' || CURRENT_DATE()
WHERE hospital_id = 'HOSP_0003'
  AND access_end_date >= CURRENT_DATE();

-- 4. Stop new data: mark the tenant inactive
UPDATE RAW_PHI.raw_hospitals SET is_active = FALSE WHERE hospital_id = 'HOSP_0003';
```

If the hospital used the analytics API, delete its entries from `ISOMETRICS_API_KEYS`
and restart the API.

**Verify**: no user other than admins and auditors can still reach the data:

```sql
SHOW GRANTS OF ROLE HOSPITAL_HOSP_0003_ANALYST;   -- should error: role does not exist
SELECT * FROM AUDIT.user_hospital_mapping
WHERE hospital_id = 'HOSP_0003' AND CURRENT_DATE() BETWEEN access_start_date AND access_end_date;
-- 0 rows
```

---

## Phase 2: Data Export (if required by contract, Day 1-7)

```sql
CREATE STAGE IF NOT EXISTS RAW_PHI.OFFBOARD_HOSP_0003_STAGE
  ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE');

COPY INTO @RAW_PHI.OFFBOARD_HOSP_0003_STAGE/encounters/
FROM (SELECT * FROM RAW_PHI.raw_encounters WHERE hospital_id = 'HOSP_0003')
FILE_FORMAT = (TYPE = PARQUET) HEADER = TRUE;
-- repeat per tenant table (list in Phase 3), deliver via the agreed secure channel,
-- then REMOVE @RAW_PHI.OFFBOARD_HOSP_0003_STAGE and drop the stage.
```

---

## Phase 3: Data Destruction (after retention window, by Day 30)

### 3.1 Record pre-deletion row counts (evidence)

```sql
CREATE TABLE IF NOT EXISTS AUDIT.offboarding_log (
    hospital_id VARCHAR(50),
    table_name VARCHAR(200),
    rows_before INTEGER,
    rows_after INTEGER,
    executed_by VARCHAR(255) DEFAULT CURRENT_USER(),
    executed_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

### 3.2 Delete from every tenant-scoped raw table

The 18 tenant tables in `RAW_PHI` (the 3 reference tables have no `hospital_id`):

```sql
EXECUTE IMMEDIATE $$
DECLARE
  tables ARRAY := ARRAY_CONSTRUCT(
    'raw_encounters', 'raw_vital_signs', 'raw_clinical_orders', 'raw_clinical_results',
    'raw_medication_administration', 'raw_patient_allergies', 'raw_problem_list',
    'raw_quality_measures', 'raw_care_plans', 'raw_referrals',
    'raw_billing_transactions', 'raw_patient_coverage', 'raw_prior_authorizations',
    'raw_sdoh_screenings', 'raw_patients', 'raw_providers', 'raw_facilities',
    'raw_hospitals');
  t STRING;
  before_count INTEGER;
  after_count INTEGER;
BEGIN
  FOR i IN 0 TO ARRAY_SIZE(tables) - 1 DO
    t := 'RAW_PHI.' || tables[i];
    SELECT COUNT(*) INTO :before_count FROM IDENTIFIER(:t) WHERE hospital_id = 'HOSP_0003';
    DELETE FROM IDENTIFIER(:t) WHERE hospital_id = 'HOSP_0003';
    SELECT COUNT(*) INTO :after_count FROM IDENTIFIER(:t) WHERE hospital_id = 'HOSP_0003';
    INSERT INTO AUDIT.offboarding_log (hospital_id, table_name, rows_before, rows_after)
      VALUES ('HOSP_0003', :t, :before_count, :after_count);
  END FOR;
  RETURN 'done';
END;
$$;
```

Child tables come first and `raw_hospitals` last, so a partial failure never leaves
orphaned clinical rows pointing at a deleted hospital.

### 3.3 Snapshots (SCD2 history)

Snapshots keep historical versions and would otherwise retain the tenant
indefinitely:

```sql
DELETE FROM SNAPSHOTS.snap_hospitals  WHERE hospital_id = 'HOSP_0003';
DELETE FROM SNAPSHOTS.snap_providers  WHERE hospital_id = 'HOSP_0003';
DELETE FROM SNAPSHOTS.snap_facilities WHERE hospital_id = 'HOSP_0003';
```

### 3.4 Rebuild marts

```bash
cd isometrics_healthcare
dbt run --target prod --select marts
# Incremental marts keep rows until rebuilt from the cleaned sources:
dbt run --target prod --select fct_encounters fct_billing_transactions --full-refresh
dbt test --target prod
```

`fct_hipaa_audit_trail` is **not** deleted: access logs are retained for 6 years
under HIPAA (45 CFR 164.316). Those rows record queries, not clinical data.

### 3.5 Time Travel and Fail-safe

Deleted rows stay recoverable through Time Travel (`DATA_RETENTION_TIME_IN_DAYS`,
default 1 day) and then Fail-safe (7 days, Snowflake-managed). Destruction is
complete only after both windows. Record the date in the certificate.

```sql
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN DATABASE ISOMETRICS_PROD;
```

---

## Phase 4: Verification & Certificate

```sql
-- Every tenant table must report 0 rows remaining
SELECT table_name, rows_before, rows_after
FROM AUDIT.offboarding_log
WHERE hospital_id = 'HOSP_0003'
ORDER BY executed_at;

-- Marts no longer contain the tenant (run as ACCOUNTADMIN, which bypasses RLS)
SELECT COUNT(*) FROM MARTS.fct_encounters WHERE hospital_id = 'HOSP_0003';  -- 0
```

Certificate of destruction contents:
- tenant, contract end date, BAA reference
- per-table row counts before and after (from `AUDIT.offboarding_log`)
- date Time Travel + Fail-safe windows elapsed
- exports delivered (if any) and their deletion date
- executed by / approved by

## Checklist

- [ ] Users disabled, hospital roles dropped, mapping rows end-dated, API keys removed
- [ ] `raw_hospitals.is_active = FALSE`
- [ ] Export delivered (if required)
- [ ] Raw tables purged (18), snapshots purged (3), marts rebuilt, tests pass
- [ ] Time Travel / Fail-safe elapsed
- [ ] Certificate of destruction issued; audit trail retained
