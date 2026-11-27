# Tenant Data Backfill Process

## Scenario
**Hospital:** Metro General Hospital (HOSP_0003)  
**Issue:** Missing 6 months of historical encounter data (July-December 2025)  
**Root Cause:** EMR system downtime during migration  
**Impact:** Incomplete clinical quality metrics, incorrect readmission rates  
**Request Date:** 2026-01-15  
**SLA:** Complete within 72 hours

---

## Phase 1: Impact Assessment (Hour 0-2)

### 1.1 Identify Missing Data Scope
```sql
-- Check data completeness by month
SELECT 
    hospital_id,
    DATE_TRUNC('month', admission_date) as month,
    COUNT(DISTINCT encounter_id) as encounter_count,
    COUNT(DISTINCT patient_id) as patient_count,
    MIN(admission_date) as earliest_admission,
    MAX(admission_date) as latest_admission
FROM raw_encounters
WHERE hospital_id = 'HOSP_0003'
  AND admission_date >= '2025-01-01'
GROUP BY hospital_id, DATE_TRUNC('month', admission_date)
ORDER BY month;

-- Expected output shows gap:
-- 2025-01: 450 encounters
-- 2025-02: 425 encounters
-- ...
-- 2025-06: 440 encounters
-- 2025-07: 0 encounters  <-- MISSING
-- 2025-08: 0 encounters  <-- MISSING
-- ...
-- 2025-12: 0 encounters  <-- MISSING
-- 2026-01: 460 encounters (current)
```

### 1.2 Impact on Downstream Metrics
```sql
-- Check affected mart tables
SELECT 
    'fct_clinical_quality_metrics' as table_name,
    COUNT(*) as row_count,
    MIN(metric_date) as min_date,
    MAX(metric_date) as max_date,
    COUNT(DISTINCT CASE WHEN metric_date BETWEEN '2025-07-01' AND '2025-12-31' 
          THEN metric_date END) as missing_days
FROM fct_clinical_quality_metrics
WHERE hospital_id = 'HOSP_0003'

UNION ALL

SELECT 
    'fct_financial_performance',
    COUNT(*),
    MIN(metric_date),
    MAX(metric_date),
    COUNT(DISTINCT CASE WHEN metric_date BETWEEN '2025-07-01' AND '2025-12-31' 
          THEN metric_date END)
FROM fct_financial_performance
WHERE hospital_id = 'HOSP_0003'

UNION ALL

SELECT 
    'fct_operational_metrics',
    COUNT(*),
    MIN(metric_date),
    MAX(metric_date),
    COUNT(DISTINCT CASE WHEN metric_date BETWEEN '2025-07-01' AND '2025-12-31' 
          THEN metric_date END)
FROM fct_operational_metrics
WHERE hospital_id = 'HOSP_0003';

-- Document impact
-- Missing Days: 184 days (Jul 1 - Dec 31)
-- Affected Tables: All clinical, financial, operational marts
-- Readmission Rate: Artificially LOW (missing subsequent admissions)
-- Financial Metrics: Incomplete revenue recognition
```

---

## Phase 2: Data Acquisition (Hour 2-8)

### 2.1 Coordinate with Hospital IT
```bash
# Email template to hospital
To: it-lead@metrogeneral.org
Subject: URGENT - Historical Data Backfill Request

We've identified a 6-month data gap (July-December 2025) for Metro General.

Required Data Files:
1. encounters_july_dec_2025.csv
2. patients_new_july_dec_2025.csv (if any new patients)
3. providers_new_july_dec_2025.csv (if any new providers)
4. billing_transactions_july_dec_2025.csv

Data Format: Same as original onboarding files
Delivery Method: Secure SFTP upload or Snowflake stage
Target Delivery: Within 6 hours
```

### 2.2 Create Backfill Staging Area
```sql
-- Create dedicated schema for backfill
CREATE SCHEMA IF NOT EXISTS BACKFILL_HOSP_0003_JAN2026
  COMMENT = 'Temporary backfill staging for Metro General - Jan 2026';

-- Create stage for file uploads
CREATE STAGE IF NOT EXISTS BACKFILL_HOSP_0003_STAGE
  FILE_FORMAT = (
    TYPE = 'CSV'
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    NULL_IF = ('NULL', 'null', '')
    EMPTY_FIELD_AS_NULL = TRUE
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
  )
  COMMENT = 'Backfill data upload stage - Metro General';

-- Create backup of current data (safety measure)
CREATE TABLE BACKFILL_HOSP_0003_JAN2026.encounters_backup AS
SELECT * FROM raw_encounters
WHERE hospital_id = 'HOSP_0003';

SELECT COUNT(*) as backup_row_count 
FROM BACKFILL_HOSP_0003_JAN2026.encounters_backup;
```

---

## Phase 3: Data Validation & Staging (Hour 8-16)

### 3.1 Upload Files to Snowflake
```bash
# Upload backfill files
snowsql -a <account> -u <user> -r DBT_PROD_ROLE <<EOF

USE SCHEMA BACKFILL_HOSP_0003_JAN2026;

PUT file://./metro_encounters_backfill.csv @BACKFILL_HOSP_0003_STAGE;
PUT file://./metro_billing_backfill.csv @BACKFILL_HOSP_0003_STAGE;

LIST @BACKFILL_HOSP_0003_STAGE;

EOF
```

### 3.2 Load into Staging Tables
```sql
-- Create staging table
CREATE OR REPLACE TABLE BACKFILL_HOSP_0003_JAN2026.encounters_staging AS
SELECT 
    $1::VARCHAR as encounter_id,
    'HOSP_0003'::VARCHAR as hospital_id,  -- Force hospital_id
    $2::VARCHAR as patient_id,
    $3::VARCHAR as provider_id,
    $4::VARCHAR as facility_id,
    $5::TIMESTAMP_NTZ as admission_date,
    $6::TIMESTAMP_NTZ as discharge_date,
    $7::NUMBER(10,2) as length_of_stay,
    $8::VARCHAR as encounter_type,
    $9::VARCHAR as admission_source,
    $10::VARCHAR as discharge_disposition,
    $11::VARCHAR as primary_diagnosis_code,
    $12::NUMBER(12,2) as total_charges,
    $13::BOOLEAN as is_readmission,
    CURRENT_TIMESTAMP() as _loaded_at,
    'BACKFILL_JAN2026' as _source_file,
    $14::TIMESTAMP_NTZ as _source_updated_at
FROM @BACKFILL_HOSP_0003_STAGE/metro_encounters_backfill.csv;

-- Validate row count
SELECT COUNT(*) as staged_row_count,
       MIN(admission_date) as earliest,
       MAX(admission_date) as latest
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging;
```

### 3.3 Data Quality Checks
```sql
-- Check 1: Date range validation
SELECT 
    COUNT(*) as total_rows,
    COUNT(CASE WHEN admission_date < '2025-07-01' THEN 1 END) as before_july,
    COUNT(CASE WHEN admission_date > '2025-12-31' THEN 1 END) as after_december,
    COUNT(CASE WHEN discharge_date < admission_date THEN 1 END) as invalid_dates,
    COUNT(CASE WHEN length_of_stay < 0 THEN 1 END) as negative_los
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging;

-- Check 2: Foreign key validation
SELECT 
    COUNT(DISTINCT e.patient_id) as unique_patients,
    COUNT(DISTINCT e.provider_id) as unique_providers,
    COUNT(DISTINCT e.facility_id) as unique_facilities,
    
    -- Check for orphaned FKs
    COUNT(DISTINCT CASE WHEN p.patient_id IS NULL THEN e.patient_id END) as orphaned_patients,
    COUNT(DISTINCT CASE WHEN pr.provider_id IS NULL THEN e.provider_id END) as orphaned_providers,
    COUNT(DISTINCT CASE WHEN f.facility_id IS NULL THEN e.facility_id END) as orphaned_facilities
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging e
LEFT JOIN raw_patients p ON e.patient_id = p.patient_id AND e.hospital_id = p.hospital_id
LEFT JOIN raw_providers pr ON e.provider_id = pr.provider_id AND e.hospital_id = pr.hospital_id
LEFT JOIN raw_facilities f ON e.facility_id = f.facility_id AND e.hospital_id = f.hospital_id;

-- Check 3: Duplicate detection
SELECT encounter_id, COUNT(*) as duplicate_count
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging
GROUP BY encounter_id
HAVING COUNT(*) > 1;

-- Check 4: Existing data overlap (prevent duplicates)
SELECT 
    COUNT(*) as overlap_count
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging staging
INNER JOIN raw_encounters existing
  ON staging.encounter_id = existing.encounter_id
  AND staging.hospital_id = existing.hospital_id;
-- Should be 0
```

### 3.4 Create Data Quality Report
```sql
-- Generate validation report
CREATE OR REPLACE VIEW BACKFILL_HOSP_0003_JAN2026.validation_report AS
SELECT 
    'Total Rows' as check_name,
    COUNT(*)::VARCHAR as result,
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END as status
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging

UNION ALL

SELECT 
    'Date Range Valid',
    COUNT(CASE WHEN admission_date BETWEEN '2025-07-01' AND '2025-12-31' THEN 1 END)::VARCHAR,
    CASE WHEN COUNT(CASE WHEN admission_date NOT BETWEEN '2025-07-01' AND '2025-12-31' THEN 1 END) = 0 
         THEN 'PASS' ELSE 'FAIL' END
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging

UNION ALL

SELECT 
    'No Duplicates',
    COUNT(DISTINCT encounter_id)::VARCHAR,
    CASE WHEN COUNT(*) = COUNT(DISTINCT encounter_id) THEN 'PASS' ELSE 'FAIL' END
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging

UNION ALL

SELECT 
    'No Orphaned Patients',
    '0'::VARCHAR,
    CASE WHEN COUNT(DISTINCT CASE WHEN p.patient_id IS NULL THEN e.patient_id END) = 0 
         THEN 'PASS' ELSE 'FAIL' END
FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging e
LEFT JOIN raw_patients p ON e.patient_id = p.patient_id AND e.hospital_id = p.hospital_id;

-- Review report
SELECT * FROM BACKFILL_HOSP_0003_JAN2026.validation_report;
```

---

## Phase 4: Backfill Execution (Hour 16-24)

### 4.1 Create Backfill Procedure
```sql
CREATE OR REPLACE PROCEDURE BACKFILL_HOSP_0003_JAN2026.execute_backfill()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    rows_inserted INTEGER;
    validation_status VARCHAR;
BEGIN
    -- Step 1: Final validation
    SELECT status INTO validation_status
    FROM BACKFILL_HOSP_0003_JAN2026.validation_report
    WHERE check_name = 'Total Rows';
    
    IF validation_status != 'PASS' THEN
        RETURN 'ABORTED: Validation failed';
    END IF;
    
    -- Step 2: Begin transaction
    BEGIN TRANSACTION;
    
    -- Step 3: Insert backfill data
    INSERT INTO raw_encounters
    SELECT * FROM BACKFILL_HOSP_0003_JAN2026.encounters_staging;
    
    GET rows_inserted = ROW_COUNT;
    
    -- Step 4: Verify insertion
    IF rows_inserted = 0 THEN
        ROLLBACK;
        RETURN 'ABORTED: No rows inserted';
    END IF;
    
    -- Step 5: Commit
    COMMIT;
    
    -- Step 6: Log success
    INSERT INTO AUDIT.backfill_log (
        hospital_id,
        backfill_date,
        table_name,
        rows_inserted,
        date_range_start,
        date_range_end,
        status
    ) VALUES (
        'HOSP_0003',
        CURRENT_TIMESTAMP(),
        'raw_encounters',
        rows_inserted,
        '2025-07-01',
        '2025-12-31',
        'SUCCESS'
    );
    
    RETURN 'SUCCESS: Inserted ' || rows_inserted || ' rows';
    
EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;
        RETURN 'ERROR: ' || SQLERRM;
END;
$$;
```

### 4.2 Execute Backfill
```sql
-- Execute the backfill
CALL BACKFILL_HOSP_0003_JAN2026.execute_backfill();

-- Verify results
SELECT 
    hospital_id,
    DATE_TRUNC('month', admission_date) as month,
    COUNT(*) as encounter_count,
    MAX(_source_file) as source
FROM raw_encounters
WHERE hospital_id = 'HOSP_0003'
  AND admission_date >= '2025-01-01'
GROUP BY hospital_id, DATE_TRUNC('month', admission_date)
ORDER BY month;

-- Should now show data for Jul-Dec 2025
```

---

## Phase 5: Downstream Impact (Hour 24-48)

### 5.1 Rebuild Affected Marts
```bash
cd isometrics_healthcare

# Staging models are views and need no refresh. Table marts rebuild on every run,
# and fct_encounters picks up the backfilled rows incrementally (it filters on
# _loaded_at, not admission date).
dbt run --target prod --select marts

# Backfilled *earlier* stays can turn already-loaded later stays into 30-day
# readmissions. Those later rows aren't reloaded incrementally, so rebuild the
# encounter fact after a historical backfill:
dbt run --target prod --select fct_encounters --full-refresh

# Snapshots record any changed dimension attributes
dbt snapshot --target prod

# Run tests to verify (readmission logic, isolation, RLS attachment)
dbt test --target prod
```

Note: there is no per-hospital dbt selector. The models process all hospitals,
and the row access policy scopes what each hospital sees.

### 5.2 Verify Mart Corrections
```sql
-- Check clinical quality metrics now populated for missing period
SELECT 
    hospital_id,
    metric_date,
    total_encounters,
    readmission_rate_30day_pct,
    mortality_rate_pct
FROM fct_clinical_quality_metrics
WHERE hospital_id = 'HOSP_0003'
  AND metric_date BETWEEN '2025-07-01' AND '2025-12-31'
ORDER BY metric_date;

-- Compare readmission rate before/after backfill
SELECT 
    'Before Backfill' as period,
    AVG(readmission_rate_30day_pct) as avg_readmission_rate
FROM fct_clinical_quality_metrics
WHERE hospital_id = 'HOSP_0003'
  AND metric_date < '2025-07-01'

UNION ALL

SELECT 
    'After Backfill (Backfilled Period)',
    AVG(readmission_rate_30day_pct)
FROM fct_clinical_quality_metrics
WHERE hospital_id = 'HOSP_0003'
  AND metric_date BETWEEN '2025-07-01' AND '2025-12-31';
```

---

## Phase 6: Validation & Sign-off (Hour 48-72)

### 6.1 Create Backfill Summary Report
```sql
CREATE OR REPLACE VIEW BACKFILL_HOSP_0003_JAN2026.backfill_summary AS
WITH before_counts AS (
    SELECT 
        'Before Backfill' as status,
        COUNT(*) as encounter_count
    FROM BACKFILL_HOSP_0003_JAN2026.encounters_backup
),
after_counts AS (
    SELECT 
        'After Backfill' as status,
        COUNT(*) as encounter_count
    FROM raw_encounters
    WHERE hospital_id = 'HOSP_0003'
),
backfill_stats AS (
    SELECT 
        COUNT(*) as rows_inserted,
        MIN(admission_date) as earliest_date,
        MAX(admission_date) as latest_date,
        COUNT(DISTINCT DATE_TRUNC('month', admission_date)) as months_filled,
        COUNT(DISTINCT patient_id) as unique_patients,
        SUM(total_charges) as total_charges_backfilled
    FROM raw_encounters
    WHERE hospital_id = 'HOSP_0003'
      AND _source_file = 'BACKFILL_JAN2026'
)
SELECT 
    b.encounter_count as encounters_before,
    a.encounter_count as encounters_after,
    s.rows_inserted,
    s.earliest_date,
    s.latest_date,
    s.months_filled,
    s.unique_patients,
    s.total_charges_backfilled
FROM before_counts b
CROSS JOIN after_counts a
CROSS JOIN backfill_stats s;

-- View summary
SELECT * FROM BACKFILL_HOSP_0003_JAN2026.backfill_summary;
```

### 6.2 Hospital Sign-off
```sql
-- Generate sign-off document
SELECT 
    'Metro General Hospital (HOSP_0003)' as hospital,
    'Backfill Complete' as status,
    CURRENT_TIMESTAMP() as completion_date,
    rows_inserted as records_added,
    earliest_date || ' to ' || latest_date as date_range,
    months_filled || ' months' as coverage,
    unique_patients || ' patients affected' as impact,
    '$' || ROUND(total_charges_backfilled, 2) || ' total charges' as financial_impact
FROM BACKFILL_HOSP_0003_JAN2026.backfill_summary;

-- Insert into permanent audit log
INSERT INTO AUDIT.backfill_completions (
    hospital_id,
    completion_timestamp,
    rows_added,
    date_range_start,
    date_range_end,
    signed_off_by,
    notes
) VALUES (
    'HOSP_0003',
    CURRENT_TIMESTAMP(),
    (SELECT rows_inserted FROM BACKFILL_HOSP_0003_JAN2026.backfill_summary),
    '2025-07-01',
    '2025-12-31',
    'it-lead@metrogeneral.org',
    'EMR migration gap backfill - All validation checks passed'
);
```

---

## Phase 7: Cleanup (Post-completion)

### 7.1 Archive Backfill Artifacts
```sql
-- Create permanent archive
CREATE SCHEMA IF NOT EXISTS BACKFILL_ARCHIVE;

CREATE TABLE BACKFILL_ARCHIVE.hosp_0003_jan2026_summary AS
SELECT * FROM BACKFILL_HOSP_0003_JAN2026.backfill_summary;

CREATE TABLE BACKFILL_ARCHIVE.hosp_0003_jan2026_validation AS
SELECT * FROM BACKFILL_HOSP_0003_JAN2026.validation_report;

-- Store audit trail
CREATE TABLE BACKFILL_ARCHIVE.hosp_0003_jan2026_audit AS
SELECT 
    'HOSP_0003' as hospital_id,
    'Jan 2026 Backfill' as project_name,
    CURRENT_TIMESTAMP() as archive_date,
    'EMR migration data gap - July-December 2025' as reason,
    (SELECT rows_inserted FROM BACKFILL_HOSP_0003_JAN2026.backfill_summary) as rows_inserted;
```

### 7.2 Remove Temporary Staging
```sql
-- Drop staging schema (after confirming success)
DROP SCHEMA IF EXISTS BACKFILL_HOSP_0003_JAN2026 CASCADE;

-- Verify cleanup
SHOW SCHEMAS LIKE 'BACKFILL%';
```

---

## Rollback Plan

If issues discovered after backfill:

```sql
-- EMERGENCY ROLLBACK PROCEDURE

-- Step 1: Restore from backup
BEGIN TRANSACTION;

-- Delete backfilled data
DELETE FROM raw_encounters
WHERE hospital_id = 'HOSP_0003'
  AND _source_file = 'BACKFILL_JAN2026';

-- Verify deletion
SELECT COUNT(*) FROM raw_encounters WHERE _source_file = 'BACKFILL_JAN2026';
-- Should be 0

COMMIT;

-- Step 2: Rebuild marts (will revert to pre-backfill state)
-- Run via dbt:
-- dbt run --full-refresh --select marts --vars '{"backfill_hospital": "HOSP_0003"}'

-- Step 3: Document rollback
INSERT INTO AUDIT.backfill_log (
    hospital_id,
    backfill_date,
    table_name,
    status,
    notes
) VALUES (
    'HOSP_0003',
    CURRENT_TIMESTAMP(),
    'raw_encounters',
    'ROLLED_BACK',
    'Reason: [describe issue]'
);
```

---

## Communication Plan

### Stakeholder Updates

**Pre-Backfill:**
```
To: Metro General Hospital Leadership
Subject: Data Backfill Scheduled - Action Required

We've identified a 6-month data gap and will perform a backfill:
- Timeline: 72 hours
- Impact: Read-only mode during backfill
- Required: Historical data files by [date]
```

**During Backfill:**
```
Status Update #1 (Hour 8): Data received, validation in progress
Status Update #2 (Hour 24): Validation complete, executing backfill
Status Update #3 (Hour 48): Backfill complete, rebuilding analytics
```

**Post-Backfill:**
```
To: Metro General Hospital Leadership
Subject: Backfill Complete - Metrics Now Accurate

Backfill successfully completed:
✓ 2,845 encounters added (July-December 2025)
✓ All metrics now accurate for the full year
✓ Readmission rate corrected from 3.2% to 8.7% (expected range)
✓ Full historical continuity restored

Your dashboards are now updated with complete data.
```

---

## Lessons Learned

**Prevention Measures:**
1. Implement data freshness monitoring alerts
2. Monthly data completeness audits
3. Automated gap detection queries
4. EMR integration health checks

**Process Improvements:**
1. Created standardized backfill procedure
2. Automated validation scripts
3. Pre-approved rollback procedures
4. Communication templates

---

## Metrics & KPIs

**Backfill Performance:**
- Total Time: 68 hours (under 72-hour SLA)
- Data Volume: 2,845 encounters, 5,690 billing transactions
- Validation Pass Rate: 100%
- Downstream Impact: 184 days of metrics corrected
- Hospital Satisfaction: ⭐⭐⭐⭐⭐ (5/5)

**Cost:**
- Labor Hours: 12 hours (data engineering)
- Compute Cost: $45.67 (Snowflake warehouse)
- Total Cost: ~$2,400 (at $200/hour labor)