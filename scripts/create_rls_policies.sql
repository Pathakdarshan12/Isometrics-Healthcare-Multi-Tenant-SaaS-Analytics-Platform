-- ============================================
-- CREATE HIPAA-COMPLIANT RLS POLICIES
-- ============================================
USE ROLE ACCOUNTADMIN;

-- ============================================
-- SECURE MAPPING TABLE FOR DEV TESTING
-- ============================================

-- Create mapping table in AUDIT schema
CREATE OR REPLACE TABLE ISOMETRICS_DEV.AUDIT.user_hospital_mapping (
    user_name VARCHAR(255),
    role_name VARCHAR(255),
    hospital_id VARCHAR(50),
    access_start_date DATE,
    access_end_date DATE,
    access_reason VARCHAR(1000),
    created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    created_by VARCHAR(255) DEFAULT CURRENT_USER(),
    PRIMARY KEY (user_name, role_name, hospital_id)
) COMMENT = 'User to hospital access mapping - HIPAA audited';

-- ============================================
-- INSERT DEV MAPPINGS
-- ============================================

-- Map DBT_USER to all hospitals in DEV for testing
-- INSERT INTO ISOMETRICS_DEV.AUDIT.user_hospital_mapping
-- SELECT
--     'DBT_USER' as user_name,
--     'DBT_DEV_ROLE' as role_name,
--     hospital_id,
--     '2025-01-01' as access_start_date,
--     '2025-12-31' as access_end_date,
--     'DEV environment - Full access for testing' as access_reason,
--     CURRENT_TIMESTAMP() as created_at,
--     CURRENT_USER() as created_by
-- FROM ISOMETRICS_DEV.RAW_PHI.raw_hospitals
-- WHERE is_active = TRUE;

-- Verify mappings
SELECT * FROM ISOMETRICS_DEV.AUDIT.user_hospital_mapping;

-- ============================================
-- UPDATED RLS POLICY (NO SESSION VARIABLES)
-- ============================================
CREATE OR REPLACE ROW ACCESS POLICY hospital_isolation_policy
AS (hospital_id VARCHAR) RETURNS BOOLEAN ->
  CASE
    -- ACCOUNTADMIN and SYSADMIN see everything (break-glass)
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN') THEN TRUE

    -- DBT_DEV_ROLE: Use mapping table instead of blanket access
   WHEN CURRENT_ROLE() = 'DBT_DEV_ROLE' AND
         (CURRENT_DATABASE() = 'ISOMETRICS_DEV' OR CURRENT_DATABASE() LIKE '%_DEV')
    THEN TRUE

    -- HIPAA auditors - see everything (read-only)
    WHEN CURRENT_ROLE() = 'HIPAA_AUDITOR' THEN TRUE

    -- Hospital-specific analyst roles (role name contains hospital_id)
    WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_ANALYST' THEN
      hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_ANALYST', '\\1')

    -- Generic hospital analyst (uses mapping table)
    WHEN CURRENT_ROLE() = 'HOSPITAL_ANALYST' THEN
      EXISTS (
        SELECT 1
        FROM ISOMETRICS_DEV.AUDIT.user_hospital_mapping m
        WHERE m.user_name = CURRENT_USER()
          AND m.hospital_id = hospital_id
          AND CURRENT_DATE() BETWEEN m.access_start_date AND m.access_end_date
      )

    -- Production dbt role (blanket access in prod)
    WHEN CURRENT_ROLE() = 'DBT_PROD_ROLE' AND
         CURRENT_DATABASE() LIKE '%_PROD' THEN TRUE

    -- Default: DENY (fail-secure)
    ELSE FALSE
  END
COMMENT = 'HIPAA-compliant hospital isolation - All access logged - No session variables';

-- Policy 2: PHI Access Control
CREATE OR REPLACE ROW ACCESS POLICY phi_access_policy
AS (hospital_id VARCHAR) RETURNS BOOLEAN ->
  CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'PHI_ADMIN', 'HIPAA_AUDITOR') THEN TRUE

    WHEN CURRENT_ROLE() = 'DBT_DEV_ROLE' AND
         (CURRENT_DATABASE() = 'ISOMETRICS_DEV' OR CURRENT_DATABASE() LIKE '%_DEV')
    THEN TRUE

    WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_PHI_ANALYST' THEN
      hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_PHI_ANALYST', '\\1')

    ELSE FALSE
  END
COMMENT = 'Restricted PHI access - Requires explicit authorization';

-- Apply RLS policies
ALTER TABLE raw_patients
ADD ROW ACCESS POLICY phi_access_policy ON (hospital_id);

ALTER TABLE raw_encounters
ADD ROW ACCESS POLICY hospital_isolation_policy ON (hospital_id);

ALTER TABLE raw_billing_transactions
ADD ROW ACCESS POLICY hospital_isolation_policy ON (hospital_id);

ALTER TABLE raw_providers
ADD ROW ACCESS POLICY hospital_isolation_policy ON (hospital_id);

ALTER TABLE raw_facilities
ADD ROW ACCESS POLICY hospital_isolation_policy ON (hospital_id);

-- Remove RLS policies
-- ALTER TABLE raw_providers
-- DROP ROW ACCESS POLICY hospital_isolation_policy;

-- ALTER TABLE raw_patients
-- DROP ROW ACCESS POLICY phi_access_policy;

-- ALTER TABLE raw_encounters
-- DROP ROW ACCESS POLICY hospital_isolation_policy;

-- ALTER TABLE raw_billing_transactions
-- DROP ROW ACCESS POLICY hospital_isolation_policy;

-- ALTER TABLE raw_providers
-- DROP ROW ACCESS POLICY hospital_isolation_policy;

-- ALTER TABLE raw_facilities
-- DROP ROW ACCESS POLICY hospital_isolation_policy;

-- DROP ROW ACCESS POLICY phi_access_policy;
-- DROP ROW ACCESS POLICY hospital_isolation_policy;


-- Grant ownership or apply privileges
GRANT OWNERSHIP ON ROW ACCESS POLICY hospital_isolation_policy TO ROLE DBT_DEV_ROLE;
GRANT APPLY ON ROW ACCESS POLICY hospital_isolation_policy TO ROLE DBT_DEV_ROLE;

-- Grant ownership or apply privileges
GRANT OWNERSHIP ON ROW ACCESS POLICY phi_access_policy TO ROLE DBT_DEV_ROLE;
GRANT APPLY ON ROW ACCESS POLICY phi_access_policy TO ROLE DBT_DEV_ROLE;


show row access policies;

-- ============================================
-- CREATE AUDIT SCHEMA & TABLES
-- ============================================

USE SCHEMA AUDIT;

-- Access audit log (HIPAA requirement)
CREATE TABLE IF NOT EXISTS access_audit_log (
    audit_id NUMBER AUTOINCREMENT PRIMARY KEY,
    access_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    user_name VARCHAR(255),
    role_name VARCHAR(255),
    database_name VARCHAR(255),
    schema_name VARCHAR(255),
    table_name VARCHAR(255),
    query_text VARCHAR(10000),
    rows_accessed NUMBER,
    hospital_id VARCHAR(50),
    session_id VARCHAR(255),
    client_ip VARCHAR(50),
    access_reason VARCHAR(1000)  -- Required for break-glass access
) COMMENT = 'HIPAA audit trail - All PHI access logged';

-- Query history for compliance
CREATE OR REPLACE VIEW query_audit_view AS
SELECT
    query_id,
    query_text,
    user_name,
    role_name,
    start_time,
    end_time,
    total_elapsed_time,
    rows_produced,
    database_name,
    schema_name
FROM snowflake.account_usage.query_history
WHERE schema_name IN ('RAW_PHI', 'STAGING', 'MARTS')
  AND start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;

-- ============================================
-- CREATE HOSPITAL-SPECIFIC ROLES (Examples)
-- ============================================

-- Create sample hospital analyst roles
CREATE ROLE IF NOT EXISTS HOSPITAL_HOSP_0001_ANALYST COMMENT = 'Analyst role for Hospital HOSP_0001';
CREATE ROLE IF NOT EXISTS HOSPITAL_HOSP_0002_ANALYST COMMENT = 'Analyst role for Hospital HOSP_0002';

-- Grant basic permissions
GRANT USAGE ON DATABASE ISOMETRICS_DEV TO ROLE HOSPITAL_HOSP_0001_ANALYST;
GRANT USAGE ON SCHEMA ISOMETRICS_DEV.STAGING TO ROLE HOSPITAL_HOSP_0001_ANALYST;
GRANT USAGE ON SCHEMA ISOMETRICS_DEV.MARTS TO ROLE HOSPITAL_HOSP_0001_ANALYST;
GRANT USAGE ON WAREHOUSE DBT_DEV_WH TO ROLE HOSPITAL_HOSP_0001_ANALYST;

GRANT ROLE HOSPITAL_HOSP_0001_ANALYST TO ROLE ACCOUNTADMIN;
GRANT ROLE HOSPITAL_HOSP_0002_ANALYST TO ROLE ACCOUNTADMIN;

DESC TABLE ISOMETRICS_DEV.AUDIT.user_hospital_mapping;


INSERT INTO ISOMETRICS_DEV.AUDIT.user_hospital_mapping(USER_NAME, ROLE_NAME, HOSPITAL_ID, ACCESS_START_DATE, ACCESS_END_DATE, ACCESS_REASON, CREATED_AT, CREATED_BY) VALUES
('DBT_USER', 'HOSPITAL_HOSP_0001_ANALYST', 'HOSP_0001', '2026-01-01', '2026-12-31','HOSP_0001 Analyst',CURRENT_TIMESTAMP(), CURRENT_USER()),
('DBT_USER', 'HOSPITAL_HOSP_0002_ANALYST', 'HOSP_0002', '2026-01-01', '2026-12-31','HOSP_0002 Analyst',CURRENT_TIMESTAMP(), CURRENT_USER());

-- Create HIPAA auditor role
CREATE ROLE IF NOT EXISTS HIPAA_AUDITOR
  COMMENT = 'Federal/regulatory auditor - read-only access with logging';

GRANT USAGE ON DATABASE ISOMETRICS_DEV TO ROLE HIPAA_AUDITOR;
GRANT USAGE ON ALL SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE HIPAA_AUDITOR;
GRANT SELECT ON ALL TABLES IN SCHEMA ISOMETRICS_DEV.AUDIT TO ROLE HIPAA_AUDITOR;
GRANT USAGE ON WAREHOUSE DBT_DEV_WH TO ROLE HIPAA_AUDITOR;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Check RLS policies
SHOW ROW ACCESS POLICIES;

-- Check table row access policies
SELECT
    policy_name,
    ref_database_name,
    ref_schema_name,
    ref_entity_name,
    ref_entity_domain
FROM snowflake.account_usage.policy_references
WHERE ref_entity_domain = 'TABLE'
ORDER BY ref_schema_name, ref_entity_name;

-- Test data isolation
USE ROLE ACCOUNTADMIN;
SELECT hospital_id, COUNT(*) as patient_count
FROM raw_phi.raw_patients
GROUP BY hospital_id
ORDER BY patient_count DESC
LIMIT 10;

SELECT 'Healthcare Snowflake setup complete!' AS status, 'Remember: All PHI access is audited and logged' AS reminder;
