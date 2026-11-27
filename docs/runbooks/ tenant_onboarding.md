# Tenant Onboarding Process

## Overview
This document outlines the process for onboarding a new hospital tenant to the IsoMetrics Healthcare Analytics Platform.

> **Conventions.** `MARTS` / `STAGING` below mean the dbt marts and staging schemas for
> the target. With dbt's default schema naming they are `<target schema>_MARTS` /
> `<target schema>_STAGING` (prod: `DBT_PROD_MARTS`, dev: `DBT_DEV_MARTS`); see
> [data_model.md](../architecture/data_model.md#schema-naming). Tenant isolation is the
> `RAW_PHI.HOSPITAL_ISOLATION_POLICY` row access policy, explained in
> [rls_implementation.md](../architecture/rls_implementation.md).

## Scenario
**New Hospital:** Riverside Medical Center  
**Hospital ID:** HOSP_0015  
**Contract Tier:** Enterprise  
**Go-Live Date:** 2026-02-01

---

## Phase 1: Infrastructure Setup (Day 1)

### 1.1 Database Objects
```sql
-- Step 1: Create hospital record in master table
USE ROLE ACCOUNTADMIN;
USE DATABASE ISOMETRICS_PROD;
USE SCHEMA RAW_PHI;

INSERT INTO raw_hospitals (
    hospital_id,
    hospital_name,
    hospital_type,
    bed_count,
    city,
    state,
    region,
    emr_system,
    contract_tier,
    contract_start_date,
    is_active,
    teaching_hospital
) VALUES (
    'HOSP_0015',
    'Riverside Medical Center',
    'community_hospital',
    350,
    'Portland',
    'OR',
    'West',
    'Epic',
    'Enterprise',
    '2026-02-01',
    TRUE,
    FALSE
);

-- Verify insertion
SELECT * FROM raw_hospitals WHERE hospital_id = 'HOSP_0015';
```

### 1.2 RLS Access Configuration
```sql
-- Step 2: Create hospital-specific analyst role
CREATE ROLE IF NOT EXISTS HOSPITAL_HOSP_0015_ANALYST 
  COMMENT = 'Analyst role for Riverside Medical Center';

-- Grant base permissions
GRANT USAGE ON DATABASE ISOMETRICS_PROD TO ROLE HOSPITAL_HOSP_0015_ANALYST;
GRANT USAGE ON SCHEMA STAGING TO ROLE HOSPITAL_HOSP_0015_ANALYST;
GRANT USAGE ON SCHEMA MARTS TO ROLE HOSPITAL_HOSP_0015_ANALYST;
GRANT USAGE ON WAREHOUSE DBT_PROD_WH TO ROLE HOSPITAL_HOSP_0015_ANALYST;

-- Grant select on all mart tables (RLS will filter)
GRANT SELECT ON ALL TABLES IN SCHEMA MARTS TO ROLE HOSPITAL_HOSP_0015_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA MARTS TO ROLE HOSPITAL_HOSP_0015_ANALYST;

-- Step 3: Add user-hospital mapping
-- Only needed for users on the generic HOSPITAL_ANALYST role. Users on the
-- hospital-specific role (HOSPITAL_HOSP_0015_ANALYST) are scoped by the role
-- name alone. The row is kept here as the access-approval audit record.
INSERT INTO AUDIT.user_hospital_mapping (
    user_name,
    role_name,
    hospital_id,
    access_start_date,
    access_end_date,
    access_reason,
    created_by
) VALUES (
    'riverside_analyst@riversidemedical.org',
    'HOSPITAL_HOSP_0015_ANALYST',
    'HOSP_0015',
    '2026-02-01',
    '2027-01-31',
    'Initial contract - Enterprise tier',
    CURRENT_USER()
);

-- Verify RLS isolation
USE ROLE HOSPITAL_HOSP_0015_ANALYST;
SELECT hospital_id, COUNT(*) 
FROM fct_encounters 
GROUP BY hospital_id;
-- Should return ONLY HOSP_0015 data
```

### 1.3 Create Hospital-Specific Users
```sql
-- Create user accounts
USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS riverside_analyst
  PASSWORD = '<generate_secure_password>'
  DEFAULT_ROLE = HOSPITAL_HOSP_0015_ANALYST
  DEFAULT_WAREHOUSE = DBT_PROD_WH
  EMAIL = 'riverside_analyst@riversidemedical.org'
  MUST_CHANGE_PASSWORD = TRUE
  COMMENT = 'Riverside Medical Center - Data Analyst';

-- Grant role to user
GRANT ROLE HOSPITAL_HOSP_0015_ANALYST TO USER riverside_analyst;

-- Create additional users as needed (finance, quality, executives)
CREATE USER IF NOT EXISTS riverside_quality
  PASSWORD = '<generate_secure_password>'
  DEFAULT_ROLE = HOSPITAL_HOSP_0015_ANALYST
  DEFAULT_WAREHOUSE = DBT_PROD_WH
  EMAIL = 'quality@riversidemedical.org'
  MUST_CHANGE_PASSWORD = TRUE
  COMMENT = 'Riverside Medical Center - Quality Analyst';

GRANT ROLE HOSPITAL_HOSP_0015_ANALYST TO USER riverside_quality;
```

---

## Phase 2: Data Migration (Days 2-5)

### 2.1 Data Staging Area
```sql
-- Create temporary staging area for onboarding
CREATE SCHEMA IF NOT EXISTS STAGING_HOSP_0015
  COMMENT = 'Temporary staging for Riverside Medical Center onboarding';

-- Create file format for hospital data
CREATE OR REPLACE FILE FORMAT RIVERSIDE_CSV_FORMAT
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  NULL_IF = ('NULL', 'null', '')
  EMPTY_FIELD_AS_NULL = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TRIM_SPACE = TRUE;

-- Create stage for data upload
CREATE STAGE IF NOT EXISTS RIVERSIDE_DATA_STAGE
  FILE_FORMAT = RIVERSIDE_CSV_FORMAT
  COMMENT = 'Data upload stage for Riverside Medical Center';
```

### 2.2 Historical Data Load
```bash
# Upload historical data files to Snowflake stage
snowsql -a <account> -u <user> -r ACCOUNTADMIN <<EOF

PUT file://./riverside_patients_historical.csv @RIVERSIDE_DATA_STAGE;
PUT file://./riverside_encounters_historical.csv @RIVERSIDE_DATA_STAGE;
PUT file://./riverside_providers_historical.csv @RIVERSIDE_DATA_STAGE;

EOF
```

### 2.3 Load into Raw Tables
```sql
-- Load patients
COPY INTO raw_patients (
    patient_id, hospital_id, mrn, first_name, last_name,
    date_of_birth, gender, race, ethnicity, zip_code,
    primary_language, marital_status, first_encounter_date,
    _loaded_at, _source_file
)
FROM (
    SELECT 
        $1::VARCHAR,
        'HOSP_0015'::VARCHAR,  -- Hard-code hospital_id
        $2::VARCHAR,
        $3::VARCHAR,
        $4::VARCHAR,
        $5::DATE,
        $6::VARCHAR,
        $7::VARCHAR,
        $8::VARCHAR,
        $9::VARCHAR,
        $10::VARCHAR,
        $11::VARCHAR,
        $12::TIMESTAMP_NTZ,
        CURRENT_TIMESTAMP(),
        METADATA$FILENAME
    FROM @RIVERSIDE_DATA_STAGE/riverside_patients_historical.csv
)
FILE_FORMAT = RIVERSIDE_CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT';

-- Verify load
SELECT 
    hospital_id,
    COUNT(*) as patient_count,
    MIN(first_encounter_date) as earliest_encounter,
    MAX(first_encounter_date) as latest_encounter
FROM raw_patients
WHERE hospital_id = 'HOSP_0015'
GROUP BY hospital_id;

-- Load encounters (similar pattern)
COPY INTO raw_encounters (
    encounter_id, hospital_id, patient_id, provider_id, facility_id,
    admission_date, discharge_date, length_of_stay, encounter_type,
    primary_diagnosis_code, total_charges, is_readmission,
    _loaded_at, _source_file
)
FROM (
    SELECT 
        $1::VARCHAR,
        'HOSP_0015'::VARCHAR,
        $2::VARCHAR,
        $3::VARCHAR,
        $4::VARCHAR,
        $5::TIMESTAMP_NTZ,
        $6::TIMESTAMP_NTZ,
        $7::NUMBER(10,2),
        $8::VARCHAR,
        $9::VARCHAR,
        $10::NUMBER(12,2),
        $11::BOOLEAN,
        CURRENT_TIMESTAMP(),
        METADATA$FILENAME
    FROM @RIVERSIDE_DATA_STAGE/riverside_encounters_historical.csv
)
FILE_FORMAT = RIVERSIDE_CSV_FORMAT
ON_ERROR = 'ABORT_STATEMENT';
```

### 2.4 Data Quality Validation
```sql
-- Run data quality checks
-- Check 1: No cross-hospital contamination
SELECT 
    e.hospital_id as encounter_hospital,
    p.hospital_id as patient_hospital,
    COUNT(*) as violation_count
FROM raw_encounters e
JOIN raw_patients p ON e.patient_id = p.patient_id
WHERE e.hospital_id = 'HOSP_0015'
  AND e.hospital_id != p.hospital_id
GROUP BY e.hospital_id, p.hospital_id;
-- Should return 0 rows

-- Check 2: Validate date ranges
SELECT 
    hospital_id,
    MIN(admission_date) as earliest_admission,
    MAX(admission_date) as latest_admission,
    COUNT(CASE WHEN discharge_date < admission_date THEN 1 END) as invalid_dates,
    COUNT(CASE WHEN length_of_stay < 0 THEN 1 END) as negative_los
FROM raw_encounters
WHERE hospital_id = 'HOSP_0015'
GROUP BY hospital_id;

-- Check 3: Validate charges
SELECT 
    hospital_id,
    COUNT(CASE WHEN total_charges < 0 THEN 1 END) as negative_charges,
    COUNT(CASE WHEN total_charges IS NULL THEN 1 END) as null_charges,
    AVG(total_charges) as avg_charge,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_charges) as median_charge
FROM raw_encounters
WHERE hospital_id = 'HOSP_0015'
GROUP BY hospital_id;
```

---

## Phase 3: dbt Integration (Day 6)

### 3.1 Initial dbt Run
```bash
# Run dbt for the new hospital
cd isometrics_healthcare

# Ensure RLS policies + mapping table exist (idempotent)
dbt run-operation setup_rls_policies --target prod

# Build all layers. Every hospital's data goes through the same models; there is
# no per-hospital selector, so this is a normal full run. Incremental marts
# (fct_encounters) pick up the newly loaded rows by their _loaded_at timestamp.
dbt run --target prod

# Run all tests (includes RLS attachment and cross-tenant checks)
dbt test --target prod

# RLS checks on their own, if you only need those
dbt test --target prod --select assert_rls_policy_applied assert_rls_column_exists \
    assert_no_cross_hospital_data_leakage assert_no_cross_hospital_encounters
```

### 3.2 Verify Mart Data
```sql
-- Check clinical quality metrics
SELECT 
    hospital_id,
    metric_date,
    total_encounters,
    readmission_rate_30day_pct,
    mortality_rate_pct,
    avg_length_of_stay
FROM fct_clinical_quality_metrics
WHERE hospital_id = 'HOSP_0015'
ORDER BY metric_date DESC
LIMIT 30;

-- Check financial performance
SELECT 
    hospital_id,
    metric_date,
    total_charges,
    total_collections,
    net_collection_rate_pct,
    denial_rate_pct
FROM fct_financial_performance
WHERE hospital_id = 'HOSP_0015'
ORDER BY metric_date DESC
LIMIT 30;

-- Check operational metrics
SELECT 
    hospital_id,
    metric_date,
    inpatient_admissions,
    emergency_visits,
    bed_occupancy_rate_pct
FROM fct_operational_metrics
WHERE hospital_id = 'HOSP_0015'
ORDER BY metric_date DESC
LIMIT 30;
```

---

## Phase 4: Dashboard & Reporting Setup (Day 7)

### 4.1 Configure Streamlit Dashboard Access
```python
# monitoring_dashboard/config/hospitals.yml
hospitals:
  - id: HOSP_0015
    name: Riverside Medical Center
    type: community_hospital
    region: West
    contract_tier: Enterprise
    features:
      - clinical_quality
      - financial_performance
      - operational_metrics
      - population_health
      - cost_attribution
    dashboards:
      - clinical_quality
      - financial
      - operations
      - population_health
```

### 4.2 Test Dashboard Access
```bash
# Test dashboard with hospital filter
streamlit run monitoring_dashboard/app.py -- --hospital HOSP_0015
```

---

## Phase 5: Training & Go-Live (Days 8-10)

### 5.1 User Training Checklist
- [ ] Dashboard navigation training
- [ ] Report generation training
- [ ] Data interpretation training
- [ ] RLS policy explanation
- [ ] Support ticket process
- [ ] Emergency contact information

### 5.2 Go-Live Validation
```sql
-- Final validation queries
-- 1. Verify user access
USE ROLE HOSPITAL_HOSP_0015_ANALYST;
SELECT CURRENT_ROLE(), CURRENT_USER(), CURRENT_DATABASE();

-- 2. Test data isolation (should only see HOSP_0015)
SELECT hospital_id, COUNT(*) 
FROM fct_encounters 
GROUP BY hospital_id;

-- 3. Verify all key metrics are populated
SELECT 
    'clinical_quality' as metric_type,
    COUNT(*) as row_count,
    MAX(metric_date) as latest_date
FROM fct_clinical_quality_metrics
WHERE hospital_id = 'HOSP_0015'
UNION ALL
SELECT 
    'financial',
    COUNT(*),
    MAX(metric_date)
FROM fct_financial_performance
WHERE hospital_id = 'HOSP_0015'
UNION ALL
SELECT 
    'operational',
    COUNT(*),
    MAX(metric_date)
FROM fct_operational_metrics
WHERE hospital_id = 'HOSP_0015';
```

---

## Phase 6: Ongoing Data Pipeline

### 6.1 Schedule Daily Incremental Loads
```sql
-- Create task for daily incremental loads
CREATE OR REPLACE TASK load_riverside_daily
  WAREHOUSE = DBT_PROD_WH
  SCHEDULE = 'USING CRON 0 2 * * * America/Los_Angeles'  -- 2 AM daily
AS
  -- This would call your ETL process
  CALL load_hospital_incremental('HOSP_0015');

-- Enable task
ALTER TASK load_riverside_daily RESUME;
```

### 6.2 Set Up Monitoring Alerts
```sql
-- Create alert for data freshness
CREATE OR REPLACE ALERT riverside_data_freshness_alert
  WAREHOUSE = DBT_PROD_WH
  SCHEDULE = '60 MINUTE'
  IF (EXISTS (
    SELECT 1
    FROM fct_sla_monitoring
    WHERE hospital_id = 'HOSP_0015'
      AND encounters_freshness_minutes > 240  -- 4 hours
      AND check_timestamp >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
  ))
  THEN CALL send_alert_email(
    'data-team@company.com',
    'Riverside Medical Center - Data Freshness SLA Breach',
    'Data freshness for HOSP_0015 has exceeded 4 hours'
  );

ALTER ALERT riverside_data_freshness_alert RESUME;
```

---

## Verification Checklist

### Infrastructure ✓
- [ ] Hospital record created in `raw_hospitals`
- [ ] RLS policy verified (only sees own data)
- [ ] User accounts created with correct roles
- [ ] Access mapping configured in `user_hospital_mapping`

### Data ✓
- [ ] Historical data loaded to raw tables
- [ ] Data quality checks passed
- [ ] No cross-hospital data leakage
- [ ] All date ranges valid
- [ ] Charges within expected ranges

### Analytics ✓
- [ ] All staging models populated
- [ ] All intermediate models populated
- [ ] All mart models populated
- [ ] dbt tests passed (100% success rate)
- [ ] Key metrics within expected ranges

### Access & Security ✓
- [ ] Users can log in successfully
- [ ] RLS prevents access to other hospitals
- [ ] Audit trail capturing all access
- [ ] Dashboard accessible with hospital filter

### Training & Support ✓
- [ ] User training completed
- [ ] Documentation provided
- [ ] Support contacts shared
- [ ] Escalation process explained

---

## Post-Onboarding (Week 2+)

### Week 1 Review Meeting
**Attendees:** Hospital analysts, IsoMetrics support, implementation lead

**Agenda:**
1. Review data quality metrics
2. Address any data discrepancies
3. Review dashboard usage
4. Answer questions
5. Gather feedback

### Monthly Business Review
- Review SLA compliance
- Review usage metrics
- Review cost attribution
- Discuss new feature requests
- Plan optimization opportunities

---

## Rollback Plan

If issues are encountered during onboarding:

```sql
-- Emergency rollback procedure
USE ROLE ACCOUNTADMIN;

-- 1. Disable user access
ALTER USER riverside_analyst SET DISABLED = TRUE;
ALTER USER riverside_quality SET DISABLED = TRUE;

-- 2. Remove from mapping table
DELETE FROM AUDIT.user_hospital_mapping
WHERE hospital_id = 'HOSP_0015';

-- 3. Soft-delete hospital data
UPDATE raw_hospitals
SET is_active = FALSE,
    deleted_at = CURRENT_TIMESTAMP()
WHERE hospital_id = 'HOSP_0015';

-- 4. Drop temporary staging
DROP SCHEMA IF EXISTS STAGING_HOSP_0015 CASCADE;

-- 5. Document rollback reason
INSERT INTO AUDIT.onboarding_log (
    hospital_id,
    status,
    notes
) VALUES (
    'HOSP_0015',
    'ROLLED_BACK',
    'Reason for rollback: [describe issue]'
);
```

---

## Success Metrics

### Week 1
- Users successfully logging in daily
- Dashboard views > 10 per day
- Zero data quality issues reported
- Zero RLS violations

### Month 1
- All key metrics being tracked
- Users self-sufficient on dashboards
- SLA compliance > 99%
- < 2 support tickets per week

### Month 3
- Hospital utilizing advanced features
- Providing feedback for improvements
- Renewing/expanding contract
- Serving as reference customer

---

## Appendix A: Common Issues & Solutions

### Issue: User can't see any data
**Solution:** Check user-hospital mapping, verify role assignment

### Issue: User sees data from other hospitals
**Solution:** CRITICAL - RLS policy breach, escalate immediately

### Issue: Metrics don't match hospital's internal reports
**Solution:** Review calculation logic with hospital, validate source data

### Issue: Slow dashboard performance
**Solution:** Check warehouse size, review query patterns, optimize clustering

---

## Appendix B: Contact Information

**Implementation Team:**
- Lead: healthcare-data-team@company.com
- Support: support@isometrics.com
- Emergency: +1-555-METRICS (24/7)

**Hospital Contacts:**
- Primary: riverside_analyst@riversidemedical.org
- Quality: quality@riversidemedical.org
- IT: it-lead@riversidemedical.org