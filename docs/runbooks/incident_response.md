# Incident Response Runbook

> **Conventions.** `MARTS` / `STAGING` below mean the dbt marts and staging schemas for
> the target. With dbt's default schema naming they are `<target schema>_MARTS` /
> `<target schema>_STAGING` (prod: `DBT_PROD_MARTS`, dev: `DBT_DEV_MARTS`); see
> [data_model.md](../architecture/data_model.md#schema-naming). Tenant isolation is the
> `RAW_PHI.HOSPITAL_ISOLATION_POLICY` row access policy, explained in
> [rls_implementation.md](../architecture/rls_implementation.md).

## 🚨 Critical Incidents

This runbook covers emergency response procedures for the IsoMetrics Healthcare Analytics Platform.

---

## Incident Classification

### Severity Levels

**P0 - Critical (Response: Immediate)**
- Data breach / unauthorized PHI access
- Complete platform outage (all hospitals)
- RLS policy failure (cross-hospital data leakage)
- Data corruption affecting patient safety

**P1 - High (Response: < 1 hour)**
- Single hospital complete outage
- Major data quality issues
- SLA breach affecting multiple hospitals
- Billing calculation errors

**P2 - Medium (Response: < 4 hours)**
- Dashboard performance issues
- Individual report failures
- Non-critical metric discrepancies

**P3 - Low (Response: Next business day)**
- Minor UI issues
- Documentation requests
- Enhancement requests

---

## Incident #1: RLS Policy Bypass Detected 🔴

### Scenario
```
ALERT: Hospital analyst from HOSP_0005 can see data from HOSP_0008
Detected: 2026-01-23 09:15 AM
Severity: P0 - CRITICAL
Impact: HIPAA violation, data breach
```

### Immediate Response (0-15 minutes)

#### Step 1: STOP THE BLEEDING
```sql
-- EXECUTE IMMEDIATELY
USE ROLE ACCOUNTADMIN;

-- 1. Disable affected user account
ALTER USER hosp_0005_analyst SET DISABLED = TRUE;

-- 2. Revoke role privileges
REVOKE ROLE HOSPITAL_HOSP_0005_ANALYST FROM USER hosp_0005_analyst;

-- 3. Document the incident
INSERT INTO AUDIT.security_incidents (
    incident_id,
    severity,
    incident_type,
    affected_users,
    detected_at,
    initial_response_by,
    status
) VALUES (
    'INC_20260123_001',
    'P0_CRITICAL',
    'RLS_POLICY_BYPASS',
    'hosp_0005_analyst',
    '2026-01-23 09:15:00',
    CURRENT_USER(),
    'CONTAINMENT_IN_PROGRESS'
);
```

#### Step 2: Assess Scope (15-30 minutes)
```sql
-- Query audit trail to determine extent of breach
SELECT 
    query_id,
    user_name,
    role_name,
    start_time,
    query_text,
    rows_produced,
    hospital_id_filter,
    is_unauthorized
FROM fct_hipaa_audit_trail
WHERE user_name = 'hosp_0005_analyst'
  AND access_timestamp >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND is_unauthorized = TRUE
ORDER BY start_time DESC;

-- Document all affected hospitals
CREATE TEMP TABLE incident_scope AS
SELECT DISTINCT
    hospital_id_filter as compromised_hospital_id,
    COUNT(DISTINCT query_id) as unauthorized_queries,
    SUM(rows_produced) as total_rows_accessed,
    MIN(start_time) as first_access,
    MAX(start_time) as last_access
FROM fct_hipaa_audit_trail
WHERE user_name = 'hosp_0005_analyst'
  AND is_unauthorized = TRUE
  AND hospital_id_filter != 'HOSP_0005'
GROUP BY hospital_id_filter;

SELECT * FROM incident_scope;
```

#### Step 3: Root Cause Analysis (30-60 minutes)
```sql
-- Check RLS policy status
SHOW ROW ACCESS POLICIES LIKE 'HOSPITAL_ISOLATION_POLICY';

-- Verify policy attachment (real time). ACCOUNT_USAGE.POLICY_REFERENCES lags by up
-- to 2 hours and can miss a policy that was just dropped; use the
-- INFORMATION_SCHEMA table function per object instead.
SELECT policy_name, policy_status, ref_arg_column_names
FROM TABLE(ISOMETRICS_PROD.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME => 'ISOMETRICS_PROD.MARTS.FCT_ENCOUNTERS',
    REF_ENTITY_DOMAIN => 'table'));
-- Or check every staging/mart model at once:
--   dbt test --target prod --select assert_rls_policy_applied

-- Verify the policy body is the current version: the mapping lookup should be
-- `hospital_id IN (SELECT m.hospital_id FROM ...user_hospital_mapping m ...)`.
-- A body with a derived table (mapped_hospital_id) errors for HOSPITAL_ANALYST
-- users ("Unsupported subquery type").
DESCRIBE ROW ACCESS POLICY ISOMETRICS_PROD.RAW_PHI.HOSPITAL_ISOLATION_POLICY;

-- Check user-hospital mapping (only consulted for the HOSPITAL_ANALYST role)
SELECT *
FROM AUDIT.user_hospital_mapping
WHERE user_name = 'hosp_0005_analyst';

-- Check the user's roles: hospital-specific roles are scoped by name
SHOW GRANTS TO USER hosp_0005_analyst;
```

Root cause checklist:

| Finding | Root cause |
|---|---|
| No policy on an object | Policy dropped by a rebuild outside dbt, or a model missing the `apply_rls_policy()` post-hook |
| `HOSPITAL_ANALYST` queries fail with "Unsupported subquery type" | Outdated body (derived-table form). Rerun `setup_rls_policies` |
| User holds a role for another hospital, or more than one hospital role | Grant error |
| Multiple active mapping rows for `HOSPITAL_ANALYST` | Mapping error (intended only for multi-hospital users) |
| A model filters on `CURRENT_ROLE()` | Code bypassing the policy (`assert_no_role_filters_in_models` should have failed CI) |

### Resolution (1-4 hours)

#### Step 1: Fix RLS Policy
```bash
cd isometrics_healthcare

# Recreate / update the policy body in place (idempotent; never touches mappings)
dbt run-operation setup_rls_policies --target prod

# Rebuild tenant-scoped models. The apply_rls_policy() post-hook re-attaches the
# policy to every staging view and mart table that's missing it.
dbt run --target prod --select staging marts

# Must pass before access is restored
dbt test --target prod --select assert_rls_policy_applied assert_rls_column_exists \
    assert_no_cross_hospital_data_leakage assert_no_cross_hospital_encounters
```

To attach the policy by hand to a single object (e.g. while dbt is unavailable):
```sql
ALTER TABLE ISOMETRICS_PROD.MARTS.FCT_ENCOUNTERS
  ADD ROW ACCESS POLICY ISOMETRICS_PROD.RAW_PHI.HOSPITAL_ISOLATION_POLICY ON (hospital_id);
-- use ALTER VIEW for staging views; Snowflake allows one row access policy per object
```

#### Step 2: Fix User Mapping
```sql
-- Ensure correct mapping
DELETE FROM AUDIT.user_hospital_mapping
WHERE user_name = 'hosp_0005_analyst';

INSERT INTO AUDIT.user_hospital_mapping (
    user_name,
    role_name,
    hospital_id,
    access_start_date,
    access_end_date,
    access_reason
) VALUES (
    'hosp_0005_analyst',
    'HOSPITAL_HOSP_0005_ANALYST',
    'HOSP_0005',
    CURRENT_DATE(),
    CURRENT_DATE() + 365,
    'Restored after security incident INC_20260123_001'
);
```

#### Step 3: Validation
```sql
-- Re-enable user account
ALTER USER hosp_0005_analyst SET DISABLED = FALSE;
GRANT ROLE HOSPITAL_HOSP_0005_ANALYST TO USER hosp_0005_analyst;

-- Test RLS enforcement (as that user)
USE ROLE HOSPITAL_HOSP_0005_ANALYST;

SELECT 
    hospital_id,
    COUNT(*) as encounter_count
FROM fct_encounters
GROUP BY hospital_id;
-- Should return ONLY HOSP_0005

-- Test cross-hospital query (should return 0 rows)
SELECT * FROM fct_encounters WHERE hospital_id = 'HOSP_0008' LIMIT 10;
-- Should return 0 rows
```

### Notification & Compliance (4-24 hours)

#### Legal Notification (HIPAA Breach)
```sql
-- Generate breach notification report
CREATE OR REPLACE VIEW incident_breach_report AS
SELECT 
    'INC_20260123_001' as incident_id,
    'HOSP_0005' as reporting_hospital,
    hospital_id_filter as affected_hospital,
    unauthorized_queries as access_count,
    total_rows_accessed as records_potentially_viewed,
    first_access as breach_start,
    last_access as breach_end,
    DATEDIFF('hour', first_access, last_access) as exposure_duration_hours
FROM incident_scope;

SELECT * FROM incident_breach_report;

-- Export for legal review
COPY INTO @INCIDENT_REPORTS/breach_20260123_001.csv
FROM incident_breach_report
FILE_FORMAT = (TYPE = CSV HEADER = TRUE);
```

#### Notification Template
```markdown
## SECURITY INCIDENT NOTIFICATION

**Incident ID:** INC_20260123_001  
**Date Detected:** January 23, 2026, 09:15 AM  
**Severity:** P0 - Critical  

### Summary
A Row-Level Security (RLS) policy configuration error allowed a user from 
Hospital A (HOSP_0005) temporary access to data from Hospital B (HOSP_0008).

### Actions Taken
1. User account immediately disabled (09:20 AM)
2. RLS policies verified and reapplied (10:30 AM)
3. Access audit completed (11:45 AM)
4. User access restored with corrected permissions (02:00 PM)

### Affected Data
- Total records potentially viewed: 147 encounters
- Time period of exposure: 72 hours
- Data types: Encounter summaries, clinical metrics (de-identified)
- NO PHI (names, addresses, SSNs) was exposed

### Root Cause
RLS policy was inadvertently dropped during a routine maintenance window 
on January 20, 2026. Detection was delayed due to monitoring gap.

### Preventive Measures
1. Implemented automated RLS policy health checks (every 15 minutes)
2. Added alerts for unauthorized cross-hospital queries
3. Enhanced post-deployment validation procedures
4. Scheduled quarterly RLS audit with external security team

### Regulatory Reporting
- HIPAA Breach Notification: Not required (< 500 individuals, no PHI exposed)
- State Breach Laws: Under review with legal counsel
- Hospital notification: Completed within 24 hours

**Contact:** security@isometrics.com | +1-555-SECURE
```

### Post-Incident Review (48 hours)

```sql
-- Create PIR (Post-Incident Review) document
CREATE TABLE AUDIT.post_incident_reviews (
    incident_id VARCHAR,
    review_date TIMESTAMP,
    root_cause TEXT,
    detection_time_minutes INT,
    resolution_time_hours INT,
    affected_hospitals INT,
    affected_records INT,
    preventive_actions TEXT,
    lessons_learned TEXT
);

INSERT INTO AUDIT.post_incident_reviews VALUES (
    'INC_20260123_001',
    CURRENT_TIMESTAMP(),
    'RLS policy dropped during maintenance, monitoring gap delayed detection',
    15,  -- Detected in 15 minutes
    5,   -- Resolved in 5 hours
    1,   -- 1 hospital affected
    147, -- 147 records potentially accessed
    'Automated RLS monitoring, enhanced deployment validation, quarterly security audits',
    'Need better change management procedures for security-critical components'
);
```

---

## Incident #2: Complete Platform Outage 🔴

### Scenario
```
ALERT: All hospitals reporting "Unable to load dashboards"
Detected: 2026-01-23 14:00 PM
Severity: P0 - CRITICAL
Impact: Complete service disruption
```

### Triage (0-5 minutes)

```sql
-- Check warehouse status
SHOW WAREHOUSES LIKE 'DBT_PROD_WH';

-- Check query history
SELECT 
    query_id,
    query_text,
    execution_status,
    error_message,
    start_time
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD('minute', -15, CURRENT_TIMESTAMP())
  AND execution_status = 'FAIL'
ORDER BY start_time DESC
LIMIT 20;

-- Check database status
SHOW DATABASES LIKE 'ISOMETRICS_PROD';
```

### Common Outage Scenarios & Solutions

#### Scenario A: Warehouse Suspended/Offline
```sql
-- Resume warehouse
ALTER WAREHOUSE DBT_PROD_WH RESUME;

-- Verify
SHOW WAREHOUSES LIKE 'DBT_PROD_WH';

-- Test query
SELECT CURRENT_TIMESTAMP();
```

#### Scenario B: Database/Schema Dropped
```sql
-- Check if database exists
SHOW DATABASES LIKE 'ISOMETRICS_PROD';

-- If missing, EMERGENCY RESTORE from time travel
CREATE DATABASE ISOMETRICS_PROD 
CLONE ISOMETRICS_PROD 
AT (TIMESTAMP => DATEADD('hour', -1, CURRENT_TIMESTAMP()));

-- Verify schemas
SHOW SCHEMAS IN DATABASE ISOMETRICS_PROD;
```

#### Scenario C: Permissions Revoked
```sql
-- Check role privileges
SHOW GRANTS TO ROLE HOSPITAL_ANALYST;

-- Restore privileges
GRANT USAGE ON DATABASE ISOMETRICS_PROD TO ROLE HOSPITAL_ANALYST;
GRANT USAGE ON SCHEMA MARTS TO ROLE HOSPITAL_ANALYST;
GRANT SELECT ON ALL TABLES IN SCHEMA MARTS TO ROLE HOSPITAL_ANALYST;
```

#### Scenario D: Bad dbt Deployment
```bash
# Rollback dbt deployment
cd isometrics_healthcare

# Check git history
git log --oneline -10

# Rollback to previous version
git checkout <previous_commit_hash>

# Redeploy
dbt run --full-refresh
```

---

## Incident #3: Data Quality Issue 🟡

### Scenario
```
ALERT: Readmission rate spike from 8% to 45% for HOSP_0003
Detected: 2026-01-23 08:00 AM
Severity: P1 - HIGH
Impact: Incorrect clinical quality metrics
```

### Investigation

```sql
-- Check raw data quality
SELECT 
    hospital_id,
    admission_date_day,
    COUNT(*) as encounter_count,
    SUM(CASE WHEN is_readmission THEN 1 ELSE 0 END) as readmissions,
    SUM(CASE WHEN is_readmission THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as readmit_rate
FROM stg_healthcare__encounters
WHERE hospital_id = 'HOSP_0003'
  AND admission_date >= CURRENT_DATE() - 30
GROUP BY hospital_id, admission_date_day
ORDER BY readmit_rate DESC;

-- Check for duplicate encounters
SELECT 
    encounter_id,
    COUNT(*) as duplicate_count
FROM raw_encounters
WHERE hospital_id = 'HOSP_0003'
GROUP BY encounter_id
HAVING COUNT(*) > 1;

-- Check readmission calculation logic. A stay is a readmission when the most
-- recent *inpatient* discharge at the same hospital was 1-30 days earlier.
SELECT
    encounter_id,
    patient_id,
    admission_date,
    discharge_date,
    previous_inpatient_encounter_id,
    previous_inpatient_discharge_date,
    days_since_last_inpatient_discharge,
    is_readmission,

    -- Recalculate manually
    CASE
        WHEN encounter_type = 'Inpatient'
         AND days_since_last_inpatient_discharge BETWEEN 1 AND 30 THEN TRUE
        ELSE FALSE
    END as should_be_readmission
FROM STAGING.stg_healthcare__encounters
WHERE hospital_id = 'HOSP_0003'
  AND is_readmission = TRUE
ORDER BY admission_date DESC
LIMIT 100;

-- Independent recomputation for all encounters (self-join, not lag()):
--   dbt test --target prod --select assert_readmission_logic_valid
```

### Resolution
```sql
-- If issue is duplicate data
DELETE FROM raw_encounters
WHERE (encounter_id, _loaded_at) IN (
    SELECT encounter_id, MAX(_loaded_at)
    FROM raw_encounters
    WHERE hospital_id = 'HOSP_0003'
    GROUP BY encounter_id
    HAVING COUNT(*) > 1
);

-- Rebuild marts
-- dbt run --full-refresh --select fct_clinical_quality_metrics
```

---

## Monitoring & Alerting

### Critical Alerts Setup

```sql
-- Alert 1: RLS Policy Health Check
-- Continuous safety net. ACCOUNT_USAGE.POLICY_REFERENCES lags by up to 2 hours,
-- so this alert can fire late. The blocking check is assert_rls_policy_applied in
-- CI/prod deploys, which reads INFORMATION_SCHEMA in real time.
CREATE OR REPLACE ALERT rls_policy_health_check
  WAREHOUSE = DBT_PROD_WH
  SCHEDULE = '15 MINUTE'
  IF (EXISTS (
    SELECT 1
    FROM information_schema.tables t
    LEFT JOIN snowflake.account_usage.policy_references pr
      ON t.table_name = pr.ref_entity_name
    WHERE t.table_schema = 'MARTS'
      AND pr.policy_name IS NULL
  ))
  THEN CALL send_pagerduty_alert(
    'P0_CRITICAL',
    'RLS Policy Missing on Mart Tables',
    'Immediate action required - data isolation at risk'
  );

-- Alert 2: Unauthorized PHI Access
CREATE OR REPLACE ALERT unauthorized_phi_access
  WAREHOUSE = DBT_PROD_WH
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1
    FROM fct_hipaa_audit_trail
    WHERE is_unauthorized = TRUE
      AND access_timestamp >= DATEADD('minute', -5, CURRENT_TIMESTAMP())
  ))
  THEN CALL send_pagerduty_alert(
    'P0_CRITICAL',
    'Unauthorized PHI Access Detected',
    'Potential HIPAA violation - investigate immediately'
  );

-- Alert 3: Data Freshness SLA
CREATE OR REPLACE ALERT data_freshness_breach
  WAREHOUSE = DBT_PROD_WH
  SCHEDULE = '30 MINUTE'
  IF (EXISTS (
    SELECT 1
    FROM fct_sla_monitoring
    WHERE freshness_sla_status = 'BREACH'
      AND check_timestamp >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
  ))
  THEN CALL send_slack_alert(
    '#data-ops',
    'Data Freshness SLA Breach',
    'One or more hospitals have data older than 6 hours'
  );
```

---

## Contact Information

### Escalation Path

**P0/P1 Incidents (24/7):**
- On-Call Engineer: +1-555-0100
- PagerDuty: pagerduty.com/isometrics
- Slack: #incident-response

**P2/P3 Incidents (Business Hours):**
- Support Email: support@isometrics.com
- Slack: #platform-support

### External Contacts

**Legal/Compliance:**
- Legal Counsel: legal@isometrics.com
- HIPAA Officer: hipaa@isometrics.com

**Vendors:**
- Snowflake Support: +1-800-SNOWFLAKE (P0 cases)
- dbt Cloud: support@getdbt.com

---

## Runbook Maintenance

This runbook should be reviewed and updated:
- After every P0/P1 incident
- Quarterly (minimum)
- When architecture changes
- When adding new hospitals

**Last Updated:** January 23, 2026  
**Next Review:** April 23, 2026  
**Owner:** Platform Engineering Team