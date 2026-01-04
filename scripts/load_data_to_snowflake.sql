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

  -- Create Parquet file format
CREATE OR REPLACE FILE FORMAT healthcare_parquet_format
  TYPE = 'PARQUET'
  COMPRESSION = 'SNAPPY'
  BINARY_AS_TEXT = FALSE
  TRIM_SPACE = TRUE
  NULL_IF = ('NULL', 'null', '', 'None');

-- Create stage
CREATE STAGE IF NOT EXISTS healthcare_data_stage
  FILE_FORMAT = healthcare_csv_format
  COMMENT = 'Staging area for healthcare CSV files';

-- ============================================
-- LOAD DATA (Run after files are uploaded)
-- ============================================
-- ============================================
-- LOAD PARQUET FILES INTO RAW TABLES
-- ============================================
-- 1. Load Hospitals
COPY INTO RAW_PHI.raw_hospitals
(hospital_id, hospital_name, hospital_type, bed_count, city, state, region,
 emr_system, contract_tier, contract_start_date, is_active, teaching_hospital,
 _loaded_at, _source_file)
FROM (
    SELECT
        $1:hospital_id::VARCHAR(50) AS hospital_id,
        $1:hospital_name::VARCHAR(255) AS hospital_name,
        $1:hospital_type::VARCHAR(100) AS hospital_type,
        $1:bed_count::NUMBER(10,0) AS bed_count,
        $1:city::VARCHAR(100) AS city,
        $1:state::VARCHAR(2) AS state,
        $1:region::VARCHAR(50) AS region,
        $1:emr_system::VARCHAR(100) AS emr_system,
        $1:contract_tier::VARCHAR(50) AS contract_tier,
        $1:contract_start_date::TIMESTAMP_NTZ AS contract_start_date,
        $1:is_active::BOOLEAN AS is_active,
        $1:teaching_hospital::BOOLEAN AS teaching_hospital,
        CURRENT_TIMESTAMP() AS _loaded_at,
        METADATA$FILENAME AS _source_file
    FROM @healthcare_data_stage/2023/hospitals.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 2. Load Patients (PHI!)
COPY INTO RAW_PHI.raw_patients
(patient_id, hospital_id, mrn, ssn_hash, first_name, last_name, date_of_birth,
 gender, race, ethnicity, zip_code, phone_number_hash, email_hash, primary_language,
 marital_status, first_encounter_date, _loaded_at, _source_file)
FROM (
    SELECT
        $1:patient_id::VARCHAR(50) AS patient_id,
        $1:hospital_id::VARCHAR(50) AS hospital_id,
        $1:mrn::VARCHAR(100) AS mrn,
        $1:ssn_hash::VARCHAR(64) AS ssn_hash,
        $1:first_name::VARCHAR(100) AS first_name,
        $1:last_name::VARCHAR(100) AS last_name,
        $1:date_of_birth::DATE AS date_of_birth,
        $1:gender::VARCHAR(20) AS gender,
        $1:race::VARCHAR(50) AS race,
        $1:ethnicity::VARCHAR(100) AS ethnicity,
        $1:zip_code::VARCHAR(10) AS zip_code,
        $1:phone_number_hash::VARCHAR(64) AS phone_number_hash,
        $1:email_hash::VARCHAR(64) AS email_hash,
        $1:primary_language::VARCHAR(50) AS primary_language,
        $1:marital_status::VARCHAR(50) AS marital_status,
        $1:first_encounter_date::TIMESTAMP_NTZ AS first_encounter_date,
        CURRENT_TIMESTAMP() AS _loaded_at,
        METADATA$FILENAME AS _source_file
    FROM @healthcare_data_stage/2023/patients.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 3. Load Providers
COPY INTO RAW_PHI.raw_providers
(provider_id, hospital_id, npi, provider_first_name, provider_last_name, specialty,
 department, provider_type, hire_date, is_active, accepts_new_patients, _loaded_at, _source_file)
FROM (
    SELECT
        $1:provider_id::VARCHAR(50) AS provider_id,
        $1:hospital_id::VARCHAR(50) AS hospital_id,
        $1:npi::VARCHAR(10) AS npi,
        $1:provider_first_name::VARCHAR(100) AS provider_first_name,
        $1:provider_last_name::VARCHAR(100) AS provider_last_name,
        $1:specialty::VARCHAR(100) AS specialty,
        $1:department::VARCHAR(100) AS department,
        $1:provider_type::VARCHAR(10) AS provider_type,
        $1:hire_date::DATE AS hire_date,
        $1:is_active::BOOLEAN AS is_active,
        $1:accepts_new_patients::BOOLEAN AS accepts_new_patients,
        CURRENT_TIMESTAMP() AS _loaded_at,
        METADATA$FILENAME AS _source_file
    FROM @healthcare_data_stage/2023/providers.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 4. Load Facilities
COPY INTO RAW_PHI.raw_facilities
(facility_id, hospital_id, facility_name, facility_type, bed_capacity, is_active,
 opened_date, _loaded_at, _source_file)
FROM (
    SELECT
        $1:facility_id::VARCHAR(50) AS facility_id,
        $1:hospital_id::VARCHAR(50) AS hospital_id,
        $1:facility_name::VARCHAR(255) AS facility_name,
        $1:facility_type::VARCHAR(100) AS facility_type,
        $1:bed_capacity::NUMBER(10,0) AS bed_capacity,
        $1:is_active::BOOLEAN AS is_active,
        $1:opened_date::TIMESTAMP_NTZ AS opened_date,
        CURRENT_TIMESTAMP() AS _loaded_at,
        METADATA$FILENAME AS _source_file
    FROM @healthcare_data_stage/2023/facilities.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 5. Load Diagnoses
COPY INTO RAW_PHI.raw_diagnoses
(diagnosis_code, diagnosis_description, category, severity_level, is_chronic, _loaded_at)
FROM (
    SELECT
        $1:diagnosis_code::VARCHAR(20) AS diagnosis_code,
        $1:diagnosis_description::VARCHAR(500) AS diagnosis_description,
        $1:category::VARCHAR(100) AS category,
        $1:severity_level::VARCHAR(50) AS severity_level,
        $1:is_chronic::BOOLEAN AS is_chronic,
        CURRENT_TIMESTAMP() AS _loaded_at
    FROM @healthcare_data_stage/2023/diagnoses.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 6. Load Procedures
COPY INTO RAW_PHI.raw_procedures
(procedure_code, procedure_description, category, typical_charge_min, typical_charge_max, _loaded_at)
FROM (
    SELECT
        $1:procedure_code::VARCHAR(20) AS procedure_code,
        $1:procedure_description::VARCHAR(500) AS procedure_description,
        $1:category::VARCHAR(100) AS category,
        $1:typical_charge_min::NUMBER(10,2) AS typical_charge_min,
        $1:typical_charge_max::NUMBER(10,2) AS typical_charge_max,
        CURRENT_TIMESTAMP() AS _loaded_at
    FROM @healthcare_data_stage/2023/procedures.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 7. Load Payers
COPY INTO RAW_PHI.raw_payers
(payer_id, payer_name, payer_type, reimbursement_rate, is_active, _loaded_at)
FROM (
    SELECT
        $1:payer_id::VARCHAR(50) AS payer_id,
        $1:payer_name::VARCHAR(255) AS payer_name,
        $1:payer_type::VARCHAR(50) AS payer_type,
        $1:reimbursement_rate::NUMBER(5,4) AS reimbursement_rate,
        $1:is_active::BOOLEAN AS is_active,
        CURRENT_TIMESTAMP() AS _loaded_at
    FROM @healthcare_data_stage/2023/payers.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 8. Load Encounters
COPY INTO RAW_PHI.raw_encounters
(encounter_id, hospital_id, patient_id, provider_id, facility_id, admission_date,
 discharge_date, length_of_stay, encounter_type, admission_source, discharge_disposition,
 primary_diagnosis_code, total_charges, is_readmission, _loaded_at, _source_file, _source_updated_at)
FROM (
    SELECT
        $1:encounter_id::VARCHAR(50) AS encounter_id,
        $1:hospital_id::VARCHAR(50) AS hospital_id,
        $1:patient_id::VARCHAR(50) AS patient_id,
        $1:provider_id::VARCHAR(50) AS provider_id,
        $1:facility_id::VARCHAR(50) AS facility_id,
        $1:admission_date::TIMESTAMP_NTZ AS admission_date,
        $1:discharge_date::TIMESTAMP_NTZ AS discharge_date,
        $1:length_of_stay::NUMBER(10,2) AS length_of_stay,
        $1:encounter_type::VARCHAR(50) AS encounter_type,
        $1:admission_source::VARCHAR(100) AS admission_source,
        $1:discharge_disposition::VARCHAR(100) AS discharge_disposition,
        $1:primary_diagnosis_code::VARCHAR(20) AS primary_diagnosis_code,
        $1:total_charges::NUMBER(12,2) AS total_charges,
        $1:is_readmission::BOOLEAN AS is_readmission,
        CURRENT_TIMESTAMP() AS _loaded_at,
        METADATA$FILENAME AS _source_file,
        $1:_source_updated_at::TIMESTAMP_NTZ AS _source_updated_at
    FROM @healthcare_data_stage/2023/encounters.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 9. Load Billing Transactions
COPY INTO RAW_PHI.raw_billing_transactions
(transaction_id, hospital_id, encounter_id, patient_id, payer_id, transaction_date,
 charge_amount, payment_amount, adjustment_amount, denial_reason, payment_status,
 _loaded_at, _source_file)
FROM (
    SELECT
        $1:transaction_id::VARCHAR(50) AS transaction_id,
        $1:hospital_id::VARCHAR(50) AS hospital_id,
        $1:encounter_id::VARCHAR(50) AS encounter_id,
        $1:patient_id::VARCHAR(50) AS patient_id,
        $1:payer_id::VARCHAR(50) AS payer_id,
        $1:transaction_date::TIMESTAMP_NTZ AS transaction_date,
        $1:charge_amount::NUMBER(12,2) AS charge_amount,
        $1:payment_amount::NUMBER(12,2) AS payment_amount,
        $1:adjustment_amount::NUMBER(12,2) AS adjustment_amount,
        $1:denial_reason::VARCHAR(255) AS denial_reason,
        $1:payment_status::VARCHAR(50) AS payment_status,
        CURRENT_TIMESTAMP() AS _loaded_at,
        METADATA$FILENAME AS _source_file
    FROM @healthcare_data_stage/2023/billing_transactions.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Check row counts for all tables
SELECT 'hospitals' AS table_name, COUNT(*) AS row_count FROM RAW_PHI.raw_hospitals
UNION ALL
SELECT 'patients', COUNT(*) FROM RAW_PHI.raw_patients
UNION ALL
SELECT 'providers', COUNT(*) FROM RAW_PHI.raw_providers
UNION ALL
SELECT 'facilities', COUNT(*) FROM RAW_PHI.raw_facilities
UNION ALL
SELECT 'diagnoses', COUNT(*) FROM RAW_PHI.raw_diagnoses
UNION ALL
SELECT 'procedures', COUNT(*) FROM RAW_PHI.raw_procedures
UNION ALL
SELECT 'payers', COUNT(*) FROM RAW_PHI.raw_payers
UNION ALL
SELECT 'encounters', COUNT(*) FROM RAW_PHI.raw_encounters
UNION ALL
SELECT 'billing_transactions', COUNT(*) FROM RAW_PHI.raw_billing_transactions
ORDER BY table_name;

-- Check for any load errors
SELECT
    TABLE_NAME,
    STATUS,
    FIRST_ERROR_MESSAGE
    FILE_NAME,
    ROW_COUNT,
    ROW_PARSED,
    FIRST_ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'RAW_HOSPITALS',
    START_TIME => DATEADD(HOURS, -1, CURRENT_TIMESTAMP())
));

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

-- Check referential integrity
SELECT
    (
        SELECT COUNT(*)
        FROM raw_encounters e
        LEFT JOIN raw_hospitals h
          ON e.hospital_id = h.hospital_id
        WHERE e.hospital_id IS NOT NULL
          AND h.hospital_id IS NULL
    ) AS "Encounters with invalid hospital_id",

    (
        SELECT COUNT(*)
        FROM raw_encounters
        WHERE hospital_id IS NULL
    ) AS "Encounters with NULL hospital_id",

    (
        SELECT COUNT(*)
        FROM raw_patients
        WHERE hospital_id IS NULL
    ) AS "Patients with NULL hospital_id";


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