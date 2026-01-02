-- ============================================
-- Load Healthcare Data into Snowflake
-- ============================================

USE DATABASE ISOMETRICS_DEV;
USE SCHEMA RAW_PHI;
USE WAREHOUSE DBT_DEV_WH;
USE ROLE ACCOUNTADMIN;

-- Create file format
CREATE OR REPLACE FILE FORMAT healthcare_csv_format
  TYPE = 'CSV'
  FIELD_DELIMITER = ','
  SKIP_HEADER = 1
  NULL_IF = ('NULL', 'null', '', 'None')
  EMPTY_FIELD_AS_NULL = TRUE
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TRIM_SPACE = TRUE;

-- Create stage
CREATE STAGE IF NOT EXISTS healthcare_data_stage
  FILE_FORMAT = healthcare_csv_format
  COMMENT = 'Staging area for healthcare CSV files';

-- List files in stage (after upload)
LIST @healthcare_data_stage;

-- ============================================
-- LOAD DATA (Run after files are uploaded)
-- ============================================

-- 1. Load Hospitals
-- Load hospitals (tenants) data from stage into table
COPY INTO RAW_PHI.raw_hospitals
(hospital_id, hospital_name, hospital_type, bed_count, city, state, region, emr_system, contract_tier, contract_start_date, is_active, teaching_hospital, _loaded_at, _source_file)
FROM (
    SELECT
        $1::VARCHAR(50)      AS hospital_id,
        $2::VARCHAR(255)     AS hospital_name,
        $3::VARCHAR(100)     AS hospital_type,
        $4::NUMBER(10,0)     AS bed_count,
        $5::VARCHAR(100)     AS city,
        $6::VARCHAR(2)       AS state,
        $7::VARCHAR(50)      AS region,
        $8::VARCHAR(100)     AS emr_system,
        $9::VARCHAR(50)      AS contract_tier,
        $10::TIMESTAMP_NTZ   AS contract_start_date,
        $11::BOOLEAN         AS is_active,
        $12::BOOLEAN         AS teaching_hospital,
        CURRENT_TIMESTAMP()  AS _loaded_at,
        METADATA$FILENAME    AS _source_file
    FROM @healthcare_data_stage/hospitals.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;


-- 2. Load Patients (PHI!)
-- Load patients (PHI - restricted) data from stage into table
COPY INTO RAW_PHI.raw_patients
( patient_id, hospital_id, mrn, ssn_hash, first_name, last_name, date_of_birth, gender, race, ethnicity, zip_code, phone_number_hash, email_hash, primary_language, marital_status, first_encounter_date, _loaded_at, _source_file)
FROM (
    SELECT
        $1::VARCHAR(50)       AS patient_id,
        $2::VARCHAR(50)       AS hospital_id,
        $3::VARCHAR(100)      AS mrn,
        $4::VARCHAR(64)       AS ssn_hash,
        $5::VARCHAR(100)      AS first_name,
        $6::VARCHAR(100)      AS last_name,
        $7::DATE              AS date_of_birth,
        $8::VARCHAR(20)       AS gender,
        $9::VARCHAR(50)       AS race,
        $10::VARCHAR(100)     AS ethnicity,
        $11::VARCHAR(10)      AS zip_code,
        $12::VARCHAR(64)      AS phone_number_hash,
        $13::VARCHAR(64)      AS email_hash,
        $14::VARCHAR(50)      AS primary_language,
        $15::VARCHAR(50)      AS marital_status,
        $16::TIMESTAMP_NTZ    AS first_encounter_date,
        CURRENT_TIMESTAMP()   AS _loaded_at,
        METADATA$FILENAME     AS _source_file
    FROM @healthcare_data_stage/patients.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 3. Load Providers
COPY INTO RAW_PHI.raw_providers
(provider_id, hospital_id, npi, provider_first_name, provider_last_name, specialty, department, provider_type, hire_date, is_active,accepts_new_patients, _loaded_at, _source_file)
FROM (
    SELECT
    $1::VARCHAR(50) AS provider_id,
    $2::VARCHAR(50) AS hospital_id,
    $3::VARCHAR(10) AS npi,
    $4::VARCHAR(100) AS provider_first_name,
    $5::VARCHAR(100) AS provider_last_name,
    $6::VARCHAR(100) AS specialty, $7::VARCHAR(100) AS department,
    $8::VARCHAR(10) AS provider_type,
    $9::DATE AS hire_date,
    $10::BOOLEAN AS is_active,
    $11::BOOLEAN AS accepts_new_patients, CURRENT_TIMESTAMP() AS _loaded_at, METADATA$FILENAME AS _source_file
    FROM @healthcare_data_stage/providers.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 4. Load Facilities
COPY INTO RAW_PHI.raw_facilities
(facility_id, hospital_id, facility_name, facility_type, bed_capacity, is_active, opened_date, _loaded_at, _source_file)
FROM (
    SELECT $1::VARCHAR(50) AS facility_id,
    $2::VARCHAR(50) AS hospital_id,
    $3::VARCHAR(255) AS facility_name,
    $4::VARCHAR(100) AS facility_type,
    $5::NUMBER(10,0) AS bed_capacity,
    $6::BOOLEAN AS is_active,
    $7::TIMESTAMP_NTZ AS opened_date, CURRENT_TIMESTAMP() AS _loaded_at, METADATA$FILENAME AS _source_file
    FROM @healthcare_data_stage/facilities.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;


-- 5. Load Diagnoses
COPY INTO RAW_PHI.raw_diagnoses
(diagnosis_code, diagnosis_description, category, severity_level, is_chronic, _loaded_at)
FROM (
    SELECT
        $1::VARCHAR(20)     AS diagnosis_code,
        $2::VARCHAR(500)    AS diagnosis_description,
        $3::VARCHAR(100)    AS category,
        $4::VARCHAR(50)     AS severity_level,
        $5::BOOLEAN         AS is_chronic,
        CURRENT_TIMESTAMP() AS _loaded_at
    FROM @healthcare_data_stage/diagnoses.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;


-- 6. Load Procedures
COPY INTO RAW_PHI.raw_procedures
(procedure_code, procedure_description, category, typical_charge_min, typical_charge_max, _loaded_at)
FROM (
    SELECT
        $1::VARCHAR(20)      AS procedure_code,
        $2::VARCHAR(500)     AS procedure_description,
        $3::VARCHAR(100)     AS category,
        $4::NUMBER(10,2)     AS typical_charge_min,
        $5::NUMBER(10,2)     AS typical_charge_max,
        CURRENT_TIMESTAMP()  AS _loaded_at
    FROM @healthcare_data_stage/procedures.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 7. Load Payers
COPY INTO RAW_PHI.raw_payers
(payer_id, payer_name, payer_type, reimbursement_rate, is_active, _loaded_at)
FROM (
    SELECT
        $1::VARCHAR(50)      AS payer_id,
        $2::VARCHAR(255)     AS payer_name,
        $3::VARCHAR(50)      AS payer_type,
        $4::NUMBER(5,4)      AS reimbursement_rate,
        $5::BOOLEAN          AS is_active,
        CURRENT_TIMESTAMP()  AS _loaded_at
    FROM @healthcare_data_stage/payers.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;


-- 8. Load Encounters
COPY INTO RAW_PHI.raw_encounters
(encounter_id, hospital_id, patient_id, provider_id, facility_id, admission_date, discharge_date, length_of_stay, encounter_type, admission_source, discharge_disposition, primary_diagnosis_code, total_charges, is_readmission, _loaded_at, _source_file, _source_updated_at)
FROM (
    SELECT
        $1::VARCHAR(50)       AS encounter_id,
        $2::VARCHAR(50)       AS hospital_id,
        $3::VARCHAR(50)       AS patient_id,
        $4::VARCHAR(50)       AS provider_id,
        $5::VARCHAR(50)       AS facility_id,
        $6::TIMESTAMP_NTZ     AS admission_date,
        $7::TIMESTAMP_NTZ     AS discharge_date,
        $8::NUMBER(10,2)      AS length_of_stay,
        $9::VARCHAR(50)       AS encounter_type,
        $10::VARCHAR(100)     AS admission_source,
        $11::VARCHAR(100)     AS discharge_disposition,
        $12::VARCHAR(20)      AS primary_diagnosis_code,
        $13::NUMBER(12,2)     AS total_charges,
        $14::BOOLEAN          AS is_readmission,
        CURRENT_TIMESTAMP()   AS _loaded_at,
        METADATA$FILENAME     AS _source_file,
        $15::TIMESTAMP_NTZ    AS _source_updated_at
    FROM @healthcare_data_stage/encounters.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;


-- 9. Load Billing Transactions
COPY INTO RAW_PHI.raw_billing_transactions
(transaction_id, hospital_id, encounter_id, patient_id, payer_id, transaction_date, charge_amount, payment_amount, adjustment_amount, denial_reason, payment_status, _loaded_at, _source_file)
FROM (
    SELECT
        $1::VARCHAR(50)       AS transaction_id,
        $2::VARCHAR(50)       AS hospital_id,
        $3::VARCHAR(50)       AS encounter_id,
        $4::VARCHAR(50)       AS patient_id,
        $5::VARCHAR(50)       AS payer_id,
        $6::TIMESTAMP_NTZ     AS transaction_date,
        $7::NUMBER(12,2)      AS charge_amount,
        $8::NUMBER(12,2)      AS payment_amount,
        $9::NUMBER(12,2)      AS adjustment_amount,
        $10::VARCHAR(255)     AS denial_reason,
        $11::VARCHAR(50)      AS payment_status,
        CURRENT_TIMESTAMP()   AS _loaded_at,
        METADATA$FILENAME     AS _source_file
    FROM @healthcare_data_stage/billing_transactions.csv
)
FILE_FORMAT = healthcare_csv_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- ============================================
-- VERIFICATION
-- ============================================

SELECT 'Hospitals' AS table_name, COUNT(*) AS row_count FROM raw_hospitals
UNION ALL
SELECT 'Patients', COUNT(*) FROM raw_patients
UNION ALL
SELECT 'Providers', COUNT(*) FROM raw_providers
UNION ALL
SELECT 'Facilities', COUNT(*) FROM raw_facilities
UNION ALL
SELECT 'Diagnoses', COUNT(*) FROM raw_diagnoses
UNION ALL
SELECT 'Procedures', COUNT(*) FROM raw_procedures
UNION ALL
SELECT 'Payers', COUNT(*) FROM raw_payers
UNION ALL
SELECT 'Encounters', COUNT(*) FROM raw_encounters
UNION ALL
SELECT 'Billing Transactions', COUNT(*) FROM raw_billing_transactions
ORDER BY table_name;

-- Check data quality
-- Check for null hospital_ids (RLS violation!)
SELECT 'Patients with NULL hospital_id' AS check_name,
       COUNT(*) AS violation_count
FROM raw_patients
WHERE hospital_id IS NULL;

SELECT 'Encounters with NULL hospital_id' AS check_name,
       COUNT(*) AS violation_count
FROM raw_encounters
WHERE hospital_id IS NULL;

-- Check referential integrity
SELECT 'Encounters with invalid hospital_id' AS check_name,
       COUNT(*) AS violation_count
FROM raw_encounters e
LEFT JOIN raw_hospitals h ON e.hospital_id = h.hospital_id
WHERE h.hospital_id IS NULL;

-- Distribution by hospital
SELECT
    h.hospital_name,
    h.hospital_type,
    COUNT(DISTINCT p.patient_id) as patient_count,
    COUNT(DISTINCT e.encounter_id) as encounter_count
FROM raw_hospitals h
LEFT JOIN raw_patients p ON h.hospital_id = p.hospital_id
LEFT JOIN raw_encounters e ON h.hospital_id = e.hospital_id
GROUP BY h.hospital_name, h.hospital_type
ORDER BY encounter_count DESC
LIMIT 10;

SELECT 'Healthcare data loaded successfully!' AS status;