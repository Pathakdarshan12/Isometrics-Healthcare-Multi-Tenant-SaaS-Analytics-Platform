-- ============================================
-- CREATE HIPAA-COMPLIANT RLS POLICIES (CI Version)
-- ============================================

USE ROLE DBT_CI_ROLE;
USE WAREHOUSE DBT_CI_WH;
USE DATABASE ISOMETRICS_CI;

-- Create AUDIT schema if it doesn't exist
CREATE SCHEMA IF NOT EXISTS AUDIT;

-- Create mapping table in AUDIT schema
CREATE OR REPLACE TABLE ISOMETRICS_CI.AUDIT.user_hospital_mapping (
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
-- UPDATED RLS POLICY - Hospital Isolation
-- ============================================
CREATE OR REPLACE ROW ACCESS POLICY ISOMETRICS_CI.AUDIT.hospital_isolation_policy
AS (hospital_id VARCHAR) RETURNS BOOLEAN ->
  CASE
    -- ACCOUNTADMIN and SYSADMIN see everything (break-glass)
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN') THEN TRUE

    -- DBT_CI_ROLE: Full access in CI environment for testing
    WHEN CURRENT_ROLE() = 'DBT_CI_ROLE' AND
         CURRENT_DATABASE() = 'ISOMETRICS_CI'
    THEN TRUE

    -- DBT_DEV_ROLE: Full access in DEV environment
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
        FROM ISOMETRICS_CI.AUDIT.user_hospital_mapping m
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
COMMENT = 'HIPAA-compliant hospital isolation - All access logged - CI environment';

-- ============================================
-- PHI Access Control Policy
-- ============================================
CREATE OR REPLACE ROW ACCESS POLICY ISOMETRICS_CI.AUDIT.phi_access_policy
AS (hospital_id VARCHAR) RETURNS BOOLEAN ->
  CASE
    -- Admin roles
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'PHI_ADMIN', 'HIPAA_AUDITOR') THEN TRUE

    -- DBT_CI_ROLE: Full access in CI environment for testing
    WHEN CURRENT_ROLE() = 'DBT_CI_ROLE' AND
         CURRENT_DATABASE() = 'ISOMETRICS_CI'
    THEN TRUE

    -- DBT_DEV_ROLE: Full access in DEV environment
    WHEN CURRENT_ROLE() = 'DBT_DEV_ROLE' AND
         (CURRENT_DATABASE() = 'ISOMETRICS_DEV' OR CURRENT_DATABASE() LIKE '%_DEV')
    THEN TRUE

    -- Hospital-specific PHI analyst roles
    WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_PHI_ANALYST' THEN
      hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_PHI_ANALYST', '\\1')

    -- Default: DENY
    ELSE FALSE
  END
COMMENT = 'Restricted PHI access - Requires explicit authorization - CI environment';

-- ============================================
-- Insert sample test data for CI
-- ============================================
INSERT INTO ISOMETRICS_CI.AUDIT.user_hospital_mapping
(user_name, role_name, hospital_id, access_start_date, access_end_date, access_reason)
VALUES
  (CURRENT_USER(), 'DBT_CI_ROLE', 'HOSP001', '2024-01-01', '2099-12-31', 'CI Testing'),
  (CURRENT_USER(), 'DBT_CI_ROLE', 'HOSP002', '2024-01-01', '2099-12-31', 'CI Testing');