-- ============================================
-- IsoMetrics Healthcare: Snowflake account bootstrap
-- ============================================
-- Run once as ACCOUNTADMIN (Snowsight worksheet -> "Run All", or
-- snow sql -f / snowsql -f). Idempotent: every statement is
-- CREATE ... IF NOT EXISTS or a GRANT, so rerunning never drops data.
--
-- Creates:
--   warehouses  DBT_DEV_WH, DBT_CI_WH, DBT_PROD_WH
--   roles       DBT_DEV_ROLE, DBT_CI_ROLE, DBT_PROD_ROLE
--   users       DBT_USER (dev + CI), DBT_PROD_USER (prod + scheduled pipeline)
--   databases   ISOMETRICS_DEV, ISOMETRICS_CI, ISOMETRICS_PROD
--   RAW_PHI + AUDIT schemas, the 21 raw tables, file formats and the stage
--   in ISOMETRICS_DEV and ISOMETRICS_PROD
--
-- Ownership model: ACCOUNTADMIN owns the raw layer; each dbt role gets only
-- what it needs (read/insert raw, create its own schemas, create the row
-- access policies in RAW_PHI). dbt roles own everything dbt builds.
--
-- After this script: set the users' RSA public keys (section 4), then follow
-- docs/setup/snowflake_setup.md.
-- ============================================
USE ROLE ACCOUNTADMIN;

-- ============================================
-- 1. WAREHOUSES
-- ============================================
CREATE WAREHOUSE IF NOT EXISTS DBT_DEV_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Development warehouse for dbt';

CREATE WAREHOUSE IF NOT EXISTS DBT_CI_WH
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'CI/CD testing warehouse';

CREATE WAREHOUSE IF NOT EXISTS DBT_PROD_WH
  WAREHOUSE_SIZE = 'SMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Production warehouse for dbt and the scheduled pipeline';

-- ============================================
-- 2. ROLES
-- ============================================
CREATE ROLE IF NOT EXISTS DBT_DEV_ROLE  COMMENT = 'dbt development';
CREATE ROLE IF NOT EXISTS DBT_CI_ROLE   COMMENT = 'dbt CI (GitHub Actions)';
CREATE ROLE IF NOT EXISTS DBT_PROD_ROLE COMMENT = 'dbt production deploys and scheduled pipeline';

-- ACCOUNTADMIN inherits the dbt roles, so it can see and manage what they build
GRANT ROLE DBT_DEV_ROLE  TO ROLE ACCOUNTADMIN;
GRANT ROLE DBT_CI_ROLE   TO ROLE ACCOUNTADMIN;
GRANT ROLE DBT_PROD_ROLE TO ROLE ACCOUNTADMIN;

GRANT USAGE ON WAREHOUSE DBT_DEV_WH  TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON WAREHOUSE DBT_CI_WH   TO ROLE DBT_CI_ROLE;
GRANT USAGE ON WAREHOUSE DBT_PROD_WH TO ROLE DBT_PROD_ROLE;

-- Observability marts (cost attribution, HIPAA audit trail, SLA) read SNOWFLAKE.ACCOUNT_USAGE
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE DBT_DEV_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE DBT_CI_ROLE;
GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE DBT_PROD_ROLE;

-- ============================================
-- 3. DATABASES AND SCHEMAS
-- ============================================
CREATE DATABASE IF NOT EXISTS ISOMETRICS_DEV  COMMENT = 'IsoMetrics development';
CREATE DATABASE IF NOT EXISTS ISOMETRICS_CI   COMMENT = 'IsoMetrics CI (per-run schemas, dropped after each run)';
CREATE DATABASE IF NOT EXISTS ISOMETRICS_PROD COMMENT = 'IsoMetrics production';

CREATE SCHEMA IF NOT EXISTS ISOMETRICS_DEV.RAW_PHI  COMMENT = 'Raw healthcare data - contains PHI - restricted';
CREATE SCHEMA IF NOT EXISTS ISOMETRICS_DEV.AUDIT    COMMENT = 'HIPAA audit trail and access mapping';
CREATE SCHEMA IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI COMMENT = 'Raw healthcare data - contains PHI - restricted';
CREATE SCHEMA IF NOT EXISTS ISOMETRICS_PROD.AUDIT   COMMENT = 'HIPAA audit trail and access mapping';

-- ============================================
-- 4. SERVICE USERS (key-pair authentication)
-- ============================================
-- Snowflake no longer allows password-only sign-in for new users, so these are
-- TYPE = SERVICE users authenticated by an RSA key pair. Generate the keys
-- (docs/setup/snowflake_setup.md, step 2) and then run, with the base64 body
-- of each PUBLIC key (no BEGIN/END lines, no line breaks):
--
--   ALTER USER DBT_USER      SET RSA_PUBLIC_KEY = 'MIIBIjANBgkq...';
--   ALTER USER DBT_PROD_USER SET RSA_PUBLIC_KEY = 'MIIBIjANBgkq...';
CREATE USER IF NOT EXISTS DBT_USER
  TYPE = SERVICE
  DEFAULT_ROLE = DBT_DEV_ROLE
  DEFAULT_WAREHOUSE = DBT_DEV_WH
  COMMENT = 'dbt / Python service user for dev and CI';

CREATE USER IF NOT EXISTS DBT_PROD_USER
  TYPE = SERVICE
  DEFAULT_ROLE = DBT_PROD_ROLE
  DEFAULT_WAREHOUSE = DBT_PROD_WH
  COMMENT = 'Production deploys and the scheduled pipeline';

GRANT ROLE DBT_DEV_ROLE  TO USER DBT_USER;
GRANT ROLE DBT_CI_ROLE   TO USER DBT_USER;
GRANT ROLE DBT_PROD_ROLE TO USER DBT_PROD_USER;

-- ============================================
-- 5. RAW TABLES (ISOMETRICS_DEV)
-- ============================================
-- data_generation/schema.py parses these CREATE TABLE statements to build the
-- Parquet schemas and the pipeline's COPY column lists: keep them the single
-- source of truth (add a column here first).
USE DATABASE ISOMETRICS_DEV;
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
    _source_file VARCHAR(500),
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'ICD-10 diagnosis codes reference';

-- Procedures (Reference table - No PHI)

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_procedures (
    procedure_code VARCHAR(20) PRIMARY KEY,
    procedure_description VARCHAR(500),
    category VARCHAR(100),
    typical_charge_min NUMBER(10,2),
    typical_charge_max NUMBER(10,2),
    _source_file VARCHAR(500),
    _loaded_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) COMMENT = 'CPT procedure codes reference';

-- Payers (Reference table - No PHI)

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_payers (
    payer_id VARCHAR(50) PRIMARY KEY,
    payer_name VARCHAR(255),
    payer_type VARCHAR(50),
    reimbursement_rate NUMBER(5,4),
    is_active BOOLEAN DEFAULT TRUE,
    _source_file VARCHAR(500),
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

-- Orders (Lab, Radiology, Medications, Procedures)

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_clinical_orders (
    order_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50), -- RLS key
    encounter_id VARCHAR(50),
    patient_id VARCHAR(50),
    provider_id VARCHAR(50),
    order_type VARCHAR(50), -- LAB | RADIOLOGY | MEDICATION | PROCEDURE
    order_code VARCHAR(20), -- CPT/LOINC/NDC code
    order_description VARCHAR(500),
    order_status VARCHAR(50), -- ORDERED | IN_PROGRESS | COMPLETED | CANCELLED
    order_datetime TIMESTAMP_NTZ,
    scheduled_datetime TIMESTAMP_NTZ,
    completed_datetime TIMESTAMP_NTZ,
    priority VARCHAR(20), -- STAT | URGENT | ROUTINE
    ordering_provider_id VARCHAR(50),
    performing_location VARCHAR(100),

    -- Medication-specific fields
    medication_name VARCHAR(255),
    dose VARCHAR(50),
    route VARCHAR(50), -- PO, IV, IM, etc.
    frequency VARCHAR(50),
    duration_days INTEGER,

    -- Lab-specific fields
    specimen_type VARCHAR(100),
    collection_datetime TIMESTAMP_NTZ,

    -- Results linkage
    result_id VARCHAR(50), -- FK to raw_clinical_results

    -- Audit
    _loaded_at TIMESTAMP_NTZ,
    _source_file VARCHAR(500),
    FOREIGN KEY (encounter_id) REFERENCES raw_encounters(encounter_id)
);

-- Results (Lab values, vital signs, imaging reports)

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_clinical_results (
    result_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50), -- RLS key
    order_id VARCHAR(50),
    patient_id VARCHAR(50),
    encounter_id VARCHAR(50),
    result_type VARCHAR(50), -- LAB | VITALS | IMAGING | PATHOLOGY

    -- Test identification
    test_code VARCHAR(20), -- LOINC code
    test_name VARCHAR(255),
    component_code VARCHAR(20), -- For panel tests
    component_name VARCHAR(255),

    -- Result values
    result_value VARCHAR(500), -- Can be numeric or text
    result_value_numeric NUMBER(18,4), -- Parsed numeric value
    result_units VARCHAR(50),
    reference_range_low NUMBER(18,4),
    reference_range_high NUMBER(18,4),
    abnormal_flag VARCHAR(10), -- H (High), L (Low), A (Abnormal), N (Normal)

    -- Timing
    result_datetime TIMESTAMP_NTZ,
    collected_datetime TIMESTAMP_NTZ,
    resulted_datetime TIMESTAMP_NTZ,

    -- Interpretation
    result_status VARCHAR(50), -- PRELIMINARY | FINAL | CORRECTED | CANCELLED
    performing_lab VARCHAR(100),
    interpreting_provider_id VARCHAR(50),

    -- Imaging-specific
    imaging_modality VARCHAR(50), -- X-RAY | CT | MRI | US
    impression TEXT, -- Radiology report impression
    report_text TEXT, -- Full report

    -- Audit
    _loaded_at TIMESTAMP_NTZ,
    FOREIGN KEY (order_id) REFERENCES raw_clinical_orders(order_id)
);

-- Vital Signs (separate from results for granular tracking)

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_vital_signs (
    vital_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    encounter_id VARCHAR(50),
    patient_id VARCHAR(50),
    measurement_datetime TIMESTAMP_NTZ,

    -- Standard vitals
    temperature_f NUMBER(5,2),
    heart_rate_bpm INTEGER,
    respiratory_rate INTEGER,
    systolic_bp INTEGER,
    diastolic_bp INTEGER,
    oxygen_saturation_pct INTEGER,
    weight_kg NUMBER(6,2),
    height_cm NUMBER(5,1),
    bmi NUMBER(4,1),

    -- Pain assessment
    pain_score INTEGER, -- 0-10 scale

    -- Calculated fields
    map_mmhg INTEGER, -- Mean Arterial Pressure

    -- Context
    position VARCHAR(50), -- SITTING | STANDING | SUPINE
    measured_by_role VARCHAR(50), -- RN | MD | MA

    _loaded_at TIMESTAMP_NTZ
);

-- Active and historical diagnoses beyond encounters

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_problem_list (
    problem_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    patient_id VARCHAR(50),

    -- Diagnosis details
    diagnosis_code VARCHAR(20), -- ICD-10
    diagnosis_description VARCHAR(500),

    -- Status tracking
    problem_status VARCHAR(50), -- ACTIVE | RESOLVED | INACTIVE
    onset_date DATE,
    resolution_date DATE,
    last_reviewed_date DATE,

    -- Clinical metadata
    severity VARCHAR(50),
    is_chronic BOOLEAN,
    is_primary_diagnosis BOOLEAN, -- For encounter linkage

    -- Documentation
    documented_by_provider_id VARCHAR(50),
    documentation_date DATE,
    clinical_notes TEXT,

    _loaded_at TIMESTAMP_NTZ
);

-- Actual medication administration (vs. orders)

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_medication_administration (
    admin_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    encounter_id VARCHAR(50),
    patient_id VARCHAR(50),
    order_id VARCHAR(50), -- FK to raw_clinical_orders

    -- Medication details
    medication_name VARCHAR(255),
    dose VARCHAR(50),
    route VARCHAR(50),

    -- Administration tracking
    scheduled_datetime TIMESTAMP_NTZ,
    administered_datetime TIMESTAMP_NTZ,
    administered_by_provider_id VARCHAR(50),
    administration_status VARCHAR(50), -- GIVEN | REFUSED | HELD | MISSED
    refusal_reason VARCHAR(255),
    hold_reason VARCHAR(255),

    -- Verification
    barcode_scanned BOOLEAN,
    witnessed_by_provider_id VARCHAR(50),

    -- Adverse reactions
    adverse_reaction_flag BOOLEAN,
    reaction_description TEXT,

    _loaded_at TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_patient_allergies (
    allergy_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    patient_id VARCHAR(50),

    -- Allergen details
    allergen_type VARCHAR(50), -- DRUG | FOOD | ENVIRONMENTAL
    allergen_code VARCHAR(20), -- RxNorm for drugs
    allergen_name VARCHAR(255),

    -- Reaction details
    reaction_type VARCHAR(100), -- ANAPHYLAXIS | RASH | GI_UPSET | etc.
    severity VARCHAR(50), -- MILD | MODERATE | SEVERE | LIFE_THREATENING

    -- Status
    allergy_status VARCHAR(50), -- ACTIVE | INACTIVE | RESOLVED
    onset_date DATE,
    resolution_date DATE,

    -- Documentation
    documented_by_provider_id VARCHAR(50),
    documentation_date DATE,
    clinical_notes TEXT,

    _loaded_at TIMESTAMP_NTZ
);

-- Nursing care plans and interventions

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_care_plans (
    care_plan_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    encounter_id VARCHAR(50),
    patient_id VARCHAR(50),

    -- Plan details
    problem_description VARCHAR(500),
    goal_description TEXT,
    intervention_description TEXT,

    -- Status
    plan_status VARCHAR(50), -- ACTIVE | ACHIEVED | DISCONTINUED
    start_date DATE,
    target_date DATE,
    completion_date DATE,

    -- Multidisciplinary team
    created_by_provider_id VARCHAR(50),
    assigned_to_provider_ids VARCHAR(500),

    -- Evaluation
    progress_notes TEXT,
    last_evaluated_date DATE,

    _loaded_at TIMESTAMP_NTZ
);

-- Patient insurance coverage (missing from current model)

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_patient_coverage (
    coverage_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    patient_id VARCHAR(50),
    payer_id VARCHAR(50), -- FK to raw_payers

    -- Policy details
    policy_number VARCHAR(100),
    group_number VARCHAR(100),
    subscriber_id VARCHAR(100),
    subscriber_name VARCHAR(255),
    subscriber_relationship VARCHAR(50), -- SELF | SPOUSE | CHILD | OTHER

    -- Coverage period
    effective_date DATE,
    termination_date DATE,
    coverage_status VARCHAR(50), -- ACTIVE | TERMINATED | SUSPENDED

    -- Coverage type
    plan_type VARCHAR(50), -- HMO | PPO | EPO | POS
    coverage_level VARCHAR(50), -- INDIVIDUAL | FAMILY

    -- Financial
    deductible_amount NUMBER(10,2),
    deductible_met_amount NUMBER(10,2),
    out_of_pocket_max NUMBER(10,2),
    out_of_pocket_met NUMBER(10,2),
    copay_amount NUMBER(10,2),
    coinsurance_pct NUMBER(5,2),

    -- Priority
    coverage_priority INTEGER, -- 1=Primary, 2=Secondary, etc.

    _loaded_at TIMESTAMP_NTZ
);

-- Prior Authorization tracking

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_prior_authorizations (
    auth_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    patient_id VARCHAR(50),
    payer_id VARCHAR(50),
    encounter_id VARCHAR(50),

    -- Authorization details
    auth_number VARCHAR(100),
    auth_type VARCHAR(50), -- SERVICE | MEDICATION | DME
    service_code VARCHAR(20), -- CPT/HCPCS
    service_description VARCHAR(500),

    -- Status tracking
    auth_status VARCHAR(50), -- PENDING | APPROVED | DENIED | EXPIRED
    request_date DATE,
    decision_date DATE,
    effective_date DATE,
    expiration_date DATE,

    -- Quantities
    units_authorized INTEGER,
    units_used INTEGER,
    units_remaining INTEGER,

    -- Clinical justification
    diagnosis_codes VARCHAR(500), -- ICD-10 codes
    clinical_notes TEXT,
    denial_reason TEXT,

    _loaded_at TIMESTAMP_NTZ
);

-- SDOH screening data (increasingly important for value-based care)

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_sdoh_screenings (
    screening_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    patient_id VARCHAR(50),
    encounter_id VARCHAR(50),
    screening_date DATE,

    -- Housing
    housing_status VARCHAR(50), -- STABLE | UNSTABLE | HOMELESS | TRANSITIONAL
    housing_concerns BOOLEAN,

    -- Food security
    food_insecurity_flag BOOLEAN,
    difficulty_affording_food BOOLEAN,

    -- Transportation
    transportation_barriers BOOLEAN,

    -- Financial strain
    difficulty_paying_utilities BOOLEAN,
    difficulty_affording_medications BOOLEAN,

    -- Social isolation
    social_isolation_score INTEGER, -- 0-10 scale

    -- Safety
    safety_concerns BOOLEAN,
    intimate_partner_violence_screen BOOLEAN,

    -- Employment
    employment_status VARCHAR(50),

    -- Education
    highest_education_level VARCHAR(50),
    health_literacy_score INTEGER,

    -- Screening tool
    screening_tool_name VARCHAR(100), -- PRAPARE, AHC, etc.

    -- Referrals made
    referrals_text TEXT,

    _loaded_at TIMESTAMP_NTZ
);

-- SDOH screening data (increasingly important for value-based care)

-- CMS Core Measures tracking

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_quality_measures (
    measure_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    encounter_id VARCHAR(50),
    patient_id VARCHAR(50),

    -- Measure identification
    measure_code VARCHAR(50), -- CMS measure ID (e.g., SEP-1)
    measure_name VARCHAR(255),
    measure_category VARCHAR(100), -- SEPSIS | AMI | STROKE | PNEUMONIA | HF

    -- Performance tracking
    numerator_eligible BOOLEAN, -- Did patient meet criteria?
    denominator_eligible BOOLEAN, -- Was patient in cohort?
    exclusion_applied BOOLEAN,
    exclusion_reason VARCHAR(255),

    -- Timing metrics (critical for many measures)
    door_to_antibiotic_minutes INTEGER, -- Sepsis
    door_to_balloon_minutes INTEGER, -- AMI
    door_to_needle_minutes INTEGER, -- Stroke

    -- Individual metric components
    metric_component VARCHAR(100),
    component_value VARCHAR(500),
    component_timestamp TIMESTAMP_NTZ,
    compliance_flag BOOLEAN,

    -- Reporting period
    reporting_quarter VARCHAR(10), -- 2024Q1
    reporting_year INTEGER,

    _loaded_at TIMESTAMP_NTZ
);

-- Outpatient referrals and care coordination

CREATE TABLE IF NOT EXISTS RAW_PHI.raw_referrals (
    referral_id VARCHAR(50) PRIMARY KEY,
    hospital_id VARCHAR(50),
    patient_id VARCHAR(50),
    encounter_id VARCHAR(50),

    -- Referral details
    referral_type VARCHAR(50), -- SPECIALIST | DME | HOME_HEALTH | SNF
    referring_provider_id VARCHAR(50),
    referred_to_provider_id VARCHAR(50),
    referred_to_facility VARCHAR(255),
    specialty VARCHAR(100),

    -- Status tracking
    referral_status VARCHAR(50), -- PENDING | SCHEDULED | COMPLETED | CANCELLED
    referral_date DATE,
    appointment_date DATE,
    completion_date DATE,

    -- Clinical details
    reason_for_referral TEXT,
    diagnosis_codes VARCHAR(500),
    urgency VARCHAR(50), -- ROUTINE | URGENT | EMERGENT

    -- Follow-up
    follow_up_required BOOLEAN,
    follow_up_completed BOOLEAN,

    _loaded_at TIMESTAMP_NTZ
);

-- ============================================
-- 6. RAW TABLES (ISOMETRICS_PROD) - same definitions
-- ============================================
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_hospitals                 LIKE ISOMETRICS_DEV.RAW_PHI.raw_hospitals;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_patients                  LIKE ISOMETRICS_DEV.RAW_PHI.raw_patients;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_providers                 LIKE ISOMETRICS_DEV.RAW_PHI.raw_providers;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_facilities                LIKE ISOMETRICS_DEV.RAW_PHI.raw_facilities;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_diagnoses                 LIKE ISOMETRICS_DEV.RAW_PHI.raw_diagnoses;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_procedures                LIKE ISOMETRICS_DEV.RAW_PHI.raw_procedures;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_payers                    LIKE ISOMETRICS_DEV.RAW_PHI.raw_payers;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_encounters                LIKE ISOMETRICS_DEV.RAW_PHI.raw_encounters;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_billing_transactions      LIKE ISOMETRICS_DEV.RAW_PHI.raw_billing_transactions;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_clinical_orders           LIKE ISOMETRICS_DEV.RAW_PHI.raw_clinical_orders;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_clinical_results          LIKE ISOMETRICS_DEV.RAW_PHI.raw_clinical_results;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_vital_signs               LIKE ISOMETRICS_DEV.RAW_PHI.raw_vital_signs;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_problem_list              LIKE ISOMETRICS_DEV.RAW_PHI.raw_problem_list;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_medication_administration LIKE ISOMETRICS_DEV.RAW_PHI.raw_medication_administration;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_patient_allergies         LIKE ISOMETRICS_DEV.RAW_PHI.raw_patient_allergies;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_care_plans                LIKE ISOMETRICS_DEV.RAW_PHI.raw_care_plans;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_patient_coverage          LIKE ISOMETRICS_DEV.RAW_PHI.raw_patient_coverage;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_prior_authorizations      LIKE ISOMETRICS_DEV.RAW_PHI.raw_prior_authorizations;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_sdoh_screenings           LIKE ISOMETRICS_DEV.RAW_PHI.raw_sdoh_screenings;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_quality_measures          LIKE ISOMETRICS_DEV.RAW_PHI.raw_quality_measures;
CREATE TABLE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.raw_referrals                 LIKE ISOMETRICS_DEV.RAW_PHI.raw_referrals;

-- ============================================
-- 7. FILE FORMATS AND STAGE (both environments)
-- ============================================
-- The stage must exist before `python -m utils.upload_files_to_stage` runs.
CREATE FILE FORMAT IF NOT EXISTS ISOMETRICS_DEV.RAW_PHI.healthcare_parquet_format
  TYPE = 'PARQUET' BINARY_AS_TEXT = FALSE TRIM_SPACE = TRUE NULL_IF = ('NULL', 'null', '', 'None');
CREATE FILE FORMAT IF NOT EXISTS ISOMETRICS_DEV.RAW_PHI.healthcare_csv_format
  TYPE = 'CSV' FIELD_DELIMITER = ',' SKIP_HEADER = 1 NULL_IF = ('NULL', 'null', '', 'None')
  EMPTY_FIELD_AS_NULL = TRUE FIELD_OPTIONALLY_ENCLOSED_BY = '"' TRIM_SPACE = TRUE;
CREATE STAGE IF NOT EXISTS ISOMETRICS_DEV.RAW_PHI.healthcare_data_stage
  FILE_FORMAT = ISOMETRICS_DEV.RAW_PHI.healthcare_parquet_format
  COMMENT = 'Landing area for generated healthcare files';

CREATE FILE FORMAT IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.healthcare_parquet_format
  TYPE = 'PARQUET' BINARY_AS_TEXT = FALSE TRIM_SPACE = TRUE NULL_IF = ('NULL', 'null', '', 'None');
CREATE FILE FORMAT IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.healthcare_csv_format
  TYPE = 'CSV' FIELD_DELIMITER = ',' SKIP_HEADER = 1 NULL_IF = ('NULL', 'null', '', 'None')
  EMPTY_FIELD_AS_NULL = TRUE FIELD_OPTIONALLY_ENCLOSED_BY = '"' TRIM_SPACE = TRUE;
CREATE STAGE IF NOT EXISTS ISOMETRICS_PROD.RAW_PHI.healthcare_data_stage
  FILE_FORMAT = ISOMETRICS_PROD.RAW_PHI.healthcare_parquet_format
  COMMENT = 'Landing area for scheduled pipeline batches';

-- ============================================
-- 8. GRANTS
-- ============================================

-- ---- DBT_DEV_ROLE -> ISOMETRICS_DEV ----
GRANT USAGE, CREATE SCHEMA, MONITOR ON DATABASE ISOMETRICS_DEV TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON SCHEMA ISOMETRICS_DEV.RAW_PHI TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON SCHEMA ISOMETRICS_DEV.AUDIT   TO ROLE DBT_DEV_ROLE;
-- setup_rls_policies creates the policies in RAW_PHI and the mapping table in AUDIT
GRANT CREATE TABLE             ON SCHEMA ISOMETRICS_DEV.AUDIT   TO ROLE DBT_DEV_ROLE;
-- read raw; insert + stage for local pipeline runs (orchestration --target dev)
GRANT SELECT, INSERT ON ALL TABLES    IN SCHEMA ISOMETRICS_DEV.RAW_PHI TO ROLE DBT_DEV_ROLE;
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA ISOMETRICS_DEV.RAW_PHI TO ROLE DBT_DEV_ROLE;
GRANT CREATE STAGE ON SCHEMA ISOMETRICS_DEV.RAW_PHI TO ROLE DBT_DEV_ROLE;
GRANT READ, WRITE ON STAGE ISOMETRICS_DEV.RAW_PHI.healthcare_data_stage TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON FILE FORMAT ISOMETRICS_DEV.RAW_PHI.healthcare_parquet_format TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON FILE FORMAT ISOMETRICS_DEV.RAW_PHI.healthcare_csv_format     TO ROLE DBT_DEV_ROLE;

-- ---- DBT_CI_ROLE -> ISOMETRICS_CI (+ read dev raw data) ----
-- CI builds into per-run schemas in ISOMETRICS_CI and reads sources from
-- ISOMETRICS_DEV.RAW_PHI (DBT_RAW_DATABASE in dbt_ci.yml).
GRANT USAGE, CREATE SCHEMA, MONITOR ON DATABASE ISOMETRICS_CI TO ROLE DBT_CI_ROLE;
GRANT USAGE ON DATABASE ISOMETRICS_DEV TO ROLE DBT_CI_ROLE;
GRANT USAGE ON SCHEMA ISOMETRICS_DEV.RAW_PHI TO ROLE DBT_CI_ROLE;
GRANT SELECT ON ALL TABLES    IN SCHEMA ISOMETRICS_DEV.RAW_PHI TO ROLE DBT_CI_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ISOMETRICS_DEV.RAW_PHI TO ROLE DBT_CI_ROLE;

-- ---- DBT_PROD_ROLE -> ISOMETRICS_PROD ----
GRANT USAGE, CREATE SCHEMA, MONITOR ON DATABASE ISOMETRICS_PROD TO ROLE DBT_PROD_ROLE;
GRANT USAGE ON SCHEMA ISOMETRICS_PROD.RAW_PHI TO ROLE DBT_PROD_ROLE;
GRANT USAGE ON SCHEMA ISOMETRICS_PROD.AUDIT   TO ROLE DBT_PROD_ROLE;
GRANT CREATE TABLE             ON SCHEMA ISOMETRICS_PROD.AUDIT   TO ROLE DBT_PROD_ROLE;
-- the scheduled pipeline PUTs batches to the stage and COPYs them into raw tables
GRANT SELECT, INSERT ON ALL TABLES    IN SCHEMA ISOMETRICS_PROD.RAW_PHI TO ROLE DBT_PROD_ROLE;
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA ISOMETRICS_PROD.RAW_PHI TO ROLE DBT_PROD_ROLE;
GRANT CREATE STAGE ON SCHEMA ISOMETRICS_PROD.RAW_PHI TO ROLE DBT_PROD_ROLE;
GRANT READ, WRITE ON STAGE ISOMETRICS_PROD.RAW_PHI.healthcare_data_stage TO ROLE DBT_PROD_ROLE;
GRANT USAGE ON FILE FORMAT ISOMETRICS_PROD.RAW_PHI.healthcare_parquet_format TO ROLE DBT_PROD_ROLE;
GRANT USAGE ON FILE FORMAT ISOMETRICS_PROD.RAW_PHI.healthcare_csv_format     TO ROLE DBT_PROD_ROLE;

-- ---- Row access policy privileges (Enterprise Edition or higher) ----
-- setup_rls_policies creates the policies in each RAW_PHI schema. Row access
-- policies do not exist on Standard Edition: there these GRANTs fail with
-- "Unsupported feature", so they are guarded to let the rest of the script finish.
-- Check: Snowsight -> Admin -> Accounts -> Edition.
EXECUTE IMMEDIATE $$
BEGIN
  GRANT CREATE ROW ACCESS POLICY ON SCHEMA ISOMETRICS_DEV.RAW_PHI  TO ROLE DBT_DEV_ROLE;
  GRANT CREATE ROW ACCESS POLICY ON SCHEMA ISOMETRICS_PROD.RAW_PHI TO ROLE DBT_PROD_ROLE;
  RETURN 'Row access policy privileges granted';
EXCEPTION
  WHEN STATEMENT_ERROR THEN
    RETURN 'NOT GRANTED: ' || SQLERRM || ' -- row access policies need Enterprise Edition; '
        || 'RLS (setup_rls_policies, the dbt post-hooks, create_rls_policies.sql) will not work on this account.';
END;
$$;

-- ============================================
-- 9. VERIFY
-- ============================================
SHOW TABLES IN SCHEMA ISOMETRICS_DEV.RAW_PHI;   -- expect 21
SHOW TABLES IN SCHEMA ISOMETRICS_PROD.RAW_PHI;  -- expect 21
SHOW GRANTS TO ROLE DBT_CI_ROLE;
DESC USER DBT_USER;                             -- RSA_PUBLIC_KEY_FP is set once the key is added

SELECT 'IsoMetrics bootstrap complete' AS status;
