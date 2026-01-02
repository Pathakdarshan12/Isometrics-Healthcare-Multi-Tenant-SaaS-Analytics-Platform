-- ============================================
-- IsoMetrics Healthcare: Snowflake Setup
-- ============================================
-- Run this script in Snowflake Worksheet as ACCOUNTADMIN
USE ROLE ACCOUNTADMIN;

-- ============================================
-- 1. CREATE DATABASES
-- ============================================

-- Development Database
CREATE DATABASE IF NOT EXISTS ISOMETRICS_DEV
  COMMENT = 'IsoMetrics Development Environment';

-- Production Database
CREATE DATABASE IF NOT EXISTS ISOMETRICS_PROD
  COMMENT = 'IsoMetrics Production Environment';

-- CI Database (for automated testing)
CREATE DATABASE IF NOT EXISTS ISOMETRICS_CI
  COMMENT = 'IsoMetrics CI/CD Testing Environment';

USE DATABASE ISOMETRICS_DEV;

-- ============================================
-- 2. CREATE HEALTHCARE SCHEMAS
-- ============================================

-- Raw data landing (PHI present, restricted access)
CREATE SCHEMA IF NOT EXISTS RAW_PHI
  COMMENT = 'Raw healthcare data - Contains PHI - Restricted Access';

-- De-identified raw data (for analytics)
CREATE SCHEMA IF NOT EXISTS RAW_DEIDENTIFIED
  COMMENT = 'Raw healthcare data - De-identified - Safe for analytics';

-- Staging layer
CREATE SCHEMA IF NOT EXISTS STAGING
  COMMENT = 'Staging models - Light transformations';

-- Intermediate layer
CREATE SCHEMA IF NOT EXISTS INTERMEDIATE
  COMMENT = 'Intermediate models - Business logic';

-- Marts layer
CREATE SCHEMA IF NOT EXISTS MARTS
  COMMENT = 'Analytics-ready dimensional models';

-- Clinical metrics
CREATE SCHEMA IF NOT EXISTS METRICS
  COMMENT = 'Pre-aggregated clinical and operational metrics';

-- Audit logs (HIPAA requirement)
CREATE SCHEMA IF NOT EXISTS AUDIT
  COMMENT = 'HIPAA audit trail and access logs';

CREATE SCHEMA IF NOT EXISTS ISOMETRICS_DEV.ELEMENTARY;

-- ============================================
-- 3. CREATE WAREHOUSES
-- ============================================

-- Development warehouse (smaller, auto-suspend quickly)
CREATE WAREHOUSE IF NOT EXISTS DBT_DEV_WH
  WITH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Development warehouse for dbt';

-- Production warehouse (larger, better performance)
CREATE WAREHOUSE IF NOT EXISTS DBT_PROD_WH
  WITH
  WAREHOUSE_SIZE = 'SMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Production warehouse for dbt';

-- CI warehouse (ephemeral, cheapest)
CREATE WAREHOUSE IF NOT EXISTS DBT_CI_WH
  WITH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'CI/CD testing warehouse';

-- ============================================
-- 4. CREATE ROLES
-- ============================================

-- Development role
CREATE ROLE IF NOT EXISTS DBT_DEV_ROLE
  COMMENT = 'Role for dbt development';

-- Production role (more restricted)
CREATE ROLE IF NOT EXISTS DBT_PROD_ROLE
  COMMENT = 'Role for dbt production deployments';

-- CI role
CREATE ROLE IF NOT EXISTS DBT_CI_ROLE
  COMMENT = 'Role for CI/CD automated testing';

-- ============================================
-- 5. GRANT PRIVILEGES
-- ============================================

-- Grant warehouse usage
GRANT USAGE ON WAREHOUSE DBT_DEV_WH TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON WAREHOUSE DBT_PROD_WH TO ROLE DBT_PROD_ROLE;
GRANT USAGE ON WAREHOUSE DBT_CI_WH TO ROLE DBT_CI_ROLE;

-- Grant database access (DEV)
-- Database level permissions
GRANT USAGE ON DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT CREATE SCHEMA ON DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT MONITOR ON DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

-- Schema level permissions (existing schemas)
GRANT USAGE ON ALL SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT CREATE TABLE ON ALL SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT CREATE VIEW ON ALL SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT MONITOR ON ALL SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

-- Schema level permissions (future schemas)
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT CREATE TABLE ON FUTURE SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT CREATE VIEW ON FUTURE SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT MONITOR ON FUTURE SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

-- Table permissions (existing tables)
GRANT SELECT ON ALL TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT INSERT ON ALL TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT UPDATE ON ALL TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT DELETE ON ALL TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT TRUNCATE ON ALL TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT REFERENCES ON ALL TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

-- Table permissions (future tables)
GRANT SELECT ON FUTURE TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT INSERT ON FUTURE TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT UPDATE ON FUTURE TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT DELETE ON FUTURE TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT TRUNCATE ON FUTURE TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT REFERENCES ON FUTURE TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

-- View permissions (existing views)
GRANT SELECT ON ALL VIEWS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT REFERENCES ON ALL VIEWS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

-- View permissions (future views)
GRANT SELECT ON FUTURE VIEWS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT REFERENCES ON FUTURE VIEWS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

-- Materialized view permissions (if you use them)
GRANT SELECT ON ALL MATERIALIZED VIEWS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT SELECT ON FUTURE MATERIALIZED VIEWS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

-- Allow role to manage stages (for seeds and data loading)
GRANT CREATE STAGE ON ALL SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT CREATE STAGE ON FUTURE SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

GRANT USAGE ON SCHEMA ISOMETRICS_DEV.ELEMENTARY TO ROLE DBT_DEV_ROLE;
GRANT CREATE TABLE ON SCHEMA ISOMETRICS_DEV.ELEMENTARY TO ROLE DBT_DEV_ROLE;
GRANT CREATE VIEW ON SCHEMA ISOMETRICS_DEV.ELEMENTARY TO ROLE DBT_DEV_ROLE;

SHOW views IN SCHEMA ISOMETRICS_DEV.ELEMENTARY;

-- Grant database access (PROD)
GRANT USAGE ON DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;
GRANT CREATE SCHEMA ON DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;
GRANT CREATE TABLE ON ALL SCHEMAS IN DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;
GRANT CREATE VIEW ON ALL SCHEMAS IN DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;

-- Grant database access (CI)
GRANT USAGE ON DATABASE ISOMETRICS_CI TO ROLE DBT_CI_ROLE;
GRANT CREATE SCHEMA ON DATABASE ISOMETRICS_CI TO ROLE DBT_CI_ROLE;
GRANT USAGE ON ALL SCHEMAS IN DATABASE ISOMETRICS_CI TO ROLE DBT_CI_ROLE;
GRANT CREATE TABLE ON ALL SCHEMAS IN DATABASE ISOMETRICS_CI TO ROLE DBT_CI_ROLE;
GRANT CREATE VIEW ON ALL SCHEMAS IN DATABASE ISOMETRICS_CI TO ROLE DBT_CI_ROLE;

-- Grant future privileges (important!)
GRANT ALL ON FUTURE SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT ALL ON FUTURE TABLES IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT ALL ON FUTURE VIEWS IN DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;

GRANT ALL ON FUTURE SCHEMAS IN DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;
GRANT ALL ON FUTURE TABLES IN DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;
GRANT ALL ON FUTURE VIEWS IN DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;

-- ============================================
-- 6. CREATE USER & ASSIGN ROLES
-- ============================================

-- Replace YOUR_PASSWORD with a strong password
CREATE USER IF NOT EXISTS DBT_USER
  PASSWORD = 'your@passwor'
  DEFAULT_ROLE = DBT_DEV_ROLE
  DEFAULT_WAREHOUSE = DBT_DEV_WH
  COMMENT = 'dbt service account';

-- Grant roles to user
GRANT ROLE DBT_DEV_ROLE TO USER DBT_USER;
GRANT ROLE DBT_PROD_ROLE TO USER DBT_USER;
GRANT ROLE DBT_CI_ROLE TO USER DBT_USER;

-- Grant roles to your admin user (replace with your username)
GRANT ROLE DBT_DEV_ROLE TO ROLE ACCOUNTADMIN;
GRANT ROLE DBT_PROD_ROLE TO ROLE ACCOUNTADMIN;

-- ============================================
-- 2. CREATE RAW TABLES (PHI Layer)
-- ============================================

USE SCHEMA RAW_PHI;

-- Hospitals (Tenants)
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_hospitals (
    hospital_id VARCHAR(50) PRIMARY KEY,
    hospital_name VARCHAR(255) NOT NULL,
    hospital_type VARCHAR(100),
    bed_count NUMBER(10,0),
    city VARCHAR(100),
    state VARCHAR(2),
    region VARCHAR(50),
    emr_system VARCHAR(100),
    contract_tier VARCHAR(50),
    contract_start_date TIMESTAMP_NTZ,
    is_active BOOLEAN DEFAULT TRUE,
    teaching_hospital BOOLEAN,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file VARCHAR(500)
) COMMENT = 'Hospital master data - Tenant information';

-- Patients (Contains PHI - Restricted!)
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_patients (
    patient_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50) NOT NULL,  -- CRITICAL for RLS
    mrn VARCHAR(100),  -- Medical Record Number (PHI)
    ssn_hash VARCHAR(64),  -- Hashed SSN (not actual SSN)
    first_name VARCHAR(100),  -- PHI
    last_name VARCHAR(100),  -- PHI
    date_of_birth DATE,  -- PHI
    gender VARCHAR(20),
    race VARCHAR(50),
    ethnicity VARCHAR(100),
    zip_code VARCHAR(10),  -- PHI (can be quasi-identifier)
    phone_number_hash VARCHAR(64),  -- Hashed
    email_hash VARCHAR(64),  -- Hashed
    primary_language VARCHAR(50),
    marital_status VARCHAR(50),
    first_encounter_date TIMESTAMP_NTZ,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file VARCHAR(500),
    FOREIGN KEY (hospital_id) REFERENCES raw_hospitals(hospital_id)
) COMMENT = 'CONTAINS PHI - Restricted Access - HIPAA Protected';

-- Providers
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_providers (
    provider_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50) NOT NULL,  -- CRITICAL for RLS
    npi VARCHAR(10),  -- National Provider Identifier
    provider_first_name VARCHAR(100),
    provider_last_name VARCHAR(100),
    specialty VARCHAR(100),
    department VARCHAR(100),
    provider_type VARCHAR(10),  -- MD, DO, NP, PA
    hire_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    accepts_new_patients BOOLEAN,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file VARCHAR(500),
    FOREIGN KEY (hospital_id) REFERENCES raw_hospitals(hospital_id)
) COMMENT = 'Provider roster - Physicians, nurses, specialists';

-- Facilities
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_facilities (
    facility_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50) NOT NULL,  -- CRITICAL for RLS
    facility_name VARCHAR(255),
    facility_type VARCHAR(100),
    bed_capacity NUMBER(10,0),
    is_active BOOLEAN DEFAULT TRUE,
    opened_date TIMESTAMP_NTZ,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file VARCHAR(500),
    FOREIGN KEY (hospital_id) REFERENCES raw_hospitals(hospital_id)
) COMMENT = 'Facility/department master data';

-- Diagnoses (Reference table - No PHI)
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_diagnoses (
    diagnosis_code VARCHAR(20) PRIMARY KEY,
    diagnosis_description VARCHAR(500),
    category VARCHAR(100),
    severity_level VARCHAR(50),
    is_chronic BOOLEAN,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'ICD-10 diagnosis codes reference';

-- Procedures (Reference table - No PHI)
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_procedures (
    procedure_code VARCHAR(20) PRIMARY KEY,
    procedure_description VARCHAR(500),
    category VARCHAR(100),
    typical_charge_min NUMBER(10,2),
    typical_charge_max NUMBER(10,2),
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'CPT procedure codes reference';

-- Payers (Reference table - No PHI)
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_payers (
    payer_id VARCHAR(50) PRIMARY KEY,
    payer_name VARCHAR(255),
    payer_type VARCHAR(50),
    reimbursement_rate NUMBER(5,4),
    is_active BOOLEAN DEFAULT TRUE,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'Insurance payer/plan reference';

-- Encounters (Contains PHI via patient_id)
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_encounters (
    encounter_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50) NOT NULL,  -- CRITICAL for RLS
    patient_id VARCHAR(50) NOT NULL,
    provider_id VARCHAR(50) NOT NULL,
    facility_id VARCHAR(50) NOT NULL,
    admission_date TIMESTAMP_NTZ NOT NULL,
    discharge_date TIMESTAMP_NTZ,
    length_of_stay NUMBER(10,2),
    encounter_type VARCHAR(50),
    admission_source VARCHAR(100),
    discharge_disposition VARCHAR(100),
    primary_diagnosis_code VARCHAR(20),
    total_charges NUMBER(12,2),
    is_readmission BOOLEAN DEFAULT FALSE,
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file VARCHAR(500),
    _source_updated_at TIMESTAMP_NTZ,
    FOREIGN KEY (hospital_id) REFERENCES raw_hospitals(hospital_id),
    FOREIGN KEY (patient_id) REFERENCES raw_patients(patient_id),
    FOREIGN KEY (provider_id) REFERENCES raw_providers(provider_id),
    FOREIGN KEY (facility_id) REFERENCES raw_facilities(facility_id),
    FOREIGN KEY (primary_diagnosis_code) REFERENCES raw_diagnoses(diagnosis_code)
) COMMENT = 'CONTAINS PHI - Patient encounters - HIPAA Protected';

-- Add clustering for performance
ALTER TABLE RAW_PHI.raw_encounters CLUSTER BY (hospital_id, admission_date);

-- Billing Transactions
CREATE TABLE IF NOT EXISTS RAW_PHI.raw_billing_transactions (
    transaction_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50) NOT NULL,  -- CRITICAL for RLS
    encounter_id VARCHAR(50) NOT NULL,
    patient_id VARCHAR(50) NOT NULL,
    payer_id VARCHAR(50) NOT NULL,
    transaction_date TIMESTAMP_NTZ,
    charge_amount NUMBER(12,2),
    payment_amount NUMBER(12,2),
    adjustment_amount NUMBER(12,2),
    denial_reason VARCHAR(255),
    payment_status VARCHAR(50),
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file VARCHAR(500),
    FOREIGN KEY (hospital_id) REFERENCES raw_hospitals(hospital_id),
    FOREIGN KEY (encounter_id) REFERENCES raw_encounters(encounter_id),
    FOREIGN KEY (patient_id) REFERENCES raw_patients(patient_id),
    FOREIGN KEY (payer_id) REFERENCES raw_payers(payer_id)
) COMMENT = 'Billing and payment transactions';

-- Add clustering
ALTER TABLE RAW_PHI.raw_billing_transactions CLUSTER BY (hospital_id, transaction_date);