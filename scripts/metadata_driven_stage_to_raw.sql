-- =======================================================================================================================================
-- ============================================== CONFIGURATION & METADATA TABLES ========================================================
-- =======================================================================================================================================
-- FILE_FORMAT_MASTER
-- Purpose: Defines reusable file format specifications
-- Answers: How to parse it?
-- ---------------------------------------------------------------------------------------------------------------------------------------
USE DATABASE ISOMETRICS_DEV;
USE SCHEMA RAW_PHI;
CREATE OR REPLACE TABLE FILE_FORMAT_MASTER (
    file_format_id        INTEGER PRIMARY KEY,
    format_name           VARCHAR(100) NOT NULL,
    format_type           VARCHAR(20) NOT NULL,
    -- Common options
    compression           VARCHAR(20),
    encoding              VARCHAR(20),
    file_extension        VARCHAR(20),
    format_options        VARIANT,
    is_active             BOOLEAN DEFAULT TRUE,
    created_by            VARCHAR(50),
    created_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at            TIMESTAMP
);
-- =======================================================================================================================================
-- SOURCE_FILE_CONFIG
-- Purpose: Defines file sources and their ingestion rules
-- Answers: What arrives and where?
-- ---------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE SOURCE_FILE_CONFIG (
    source_id           INTEGER PRIMARY KEY,
    source_name         VARCHAR(100) UNIQUE,
    source_system       VARCHAR(50),        -- SAP | SALESFORCE | API
    file_format_id      INTEGER,            -- FK → FILE_FORMAT_MASTER
    landing_path        VARCHAR(500),       -- s3://bucket/raw/orders/, INSERT CDC_STREAM NAME IN CASE OF STREAM EX- BRONZE.STREAM_ORDERS_CHANGES:
    file_pattern        VARCHAR(100),       -- orders_*.csv | orders_{YYYY}{MM}{DD}.csv
    ingestion_type      VARCHAR(20),        -- BATCH | STREAM | INCREMENTAL
    schedule_cron       VARCHAR(50),        -- 0 2 * * * (daily 2 AM)
    active_flag         CHAR(1) DEFAULT 'Y',
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (file_format_id) REFERENCES FILE_FORMAT_MASTER(file_format_id)
);
-- ======================================================================================================================================
-- DATA_FIELD_MASTER
-- Purpose: Canonical definition of business fields (logical schema)
-- Answers: How it is structured?
-- ---------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE DATA_FIELD_MASTER (
    field_id                INTEGER PRIMARY KEY,
    field_name              VARCHAR(100) UNIQUE,
    data_type               VARCHAR(20),        -- VARCHAR | INTEGER | DATE | TIMESTAMP | NUMBER
    length                  INTEGER,
    precision               INTEGER,
    scale                   INTEGER,
    nullable_flag           CHAR(1) DEFAULT 'Y',
    business_description    VARCHAR(500),
    data_domain             VARCHAR(50),        -- CUSTOMER | ORDER | PRODUCT
    pii_flag                CHAR(1) DEFAULT 'N',
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- =======================================================================================================================================
-- FILE_COLUMN_MAPPING
-- Purpose: Maps physical file columns to logical business fields
-- Answers: How to transform source → target?
-- ---------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE FILE_COLUMN_MAPPING (
    mapping_id              INTEGER PRIMARY KEY,
    source_id               INTEGER,
    file_column_name        VARCHAR(100),
    field_id                INTEGER,
    column_position         INTEGER,
    is_primary_key          BOOLEAN DEFAULT FALSE,
    auto_increment_flag     BOOLEAN DEFAULT FALSE,  -- NEW: Tracks if PK is auto-generated
    transformation_rule     VARCHAR(50000),
    default_value           VARCHAR(100),           -- NEW: Use UUID_STRING() for non-auto PKs
    validation_rule         VARCHAR(500),
    active_flag             CHAR(1) DEFAULT 'Y',
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (source_id) REFERENCES RAW_PHI.SOURCE_FILE_CONFIG(source_id),
    FOREIGN KEY (field_id) REFERENCES RAW_PHI.DATA_FIELD_MASTER(field_id)
);
-- =======================================================================================================================================
-- RAW_TABLE_MAPPING
-- Purpose: Defines where parsed data lands
-- Answers: Where it lands?
-- ---------------------------------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE TABLE RAW_TABLE_MAPPING (
    target_id               INTEGER PRIMARY KEY,
    source_id               INTEGER,
    raw_table               VARCHAR(100),
    load_error_table        VARCHAR(100),
    load_type               VARCHAR(20),        -- APPEND | MERGE | FULL_REFRESH
    primary_key_fields      VARCHAR(200),
    partition_columns       VARCHAR(200),
    clustering_columns      VARCHAR(200),
    merge_key_fields        VARCHAR(200),
    enable_raw_columns      CHAR(1) DEFAULT 'Y',
    enable_audit_columns    CHAR(1) DEFAULT 'Y',
    active_flag             CHAR(1) DEFAULT 'Y',
    created_at              TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (source_id) REFERENCES RAW_PHI.SOURCE_FILE_CONFIG(source_id)
);

-- =====================================================
-- BATCH TABLE - STORES BATCH EXECUTION DATA
-- =====================================================
CREATE OR REPLACE TABLE BATCH_RUN_LOG (
    batch_id                VARCHAR(50) PRIMARY KEY,
    batch_run_date          DATE,
    batch_run_timestamp     TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    source_id               INTEGER,
    source_name             VARCHAR(100),
    raw_table               VARCHAR(100),
    load_type               VARCHAR(20),
    batch_status            VARCHAR(20),        -- STARTED | SUCCESS | FAILED | PARTIAL
    records_read            INTEGER,
    records_inserted        INTEGER,
    records_updated         INTEGER,
    records_deleted         INTEGER,
    records_error           INTEGER,
    files_processed         INTEGER,
    file_names              VARCHAR(5000),
    start_time              TIMESTAMP,
    end_time                TIMESTAMP,
    duration_seconds        NUMBER(10,2),
    error_message           VARCHAR(5000),
    created_by              VARCHAR(100) DEFAULT CURRENT_USER(),
    FOREIGN KEY (source_id) REFERENCES RAW_PHI.SOURCE_FILE_CONFIG(source_id)
);

-- =======================================================================================================================================
-- FILE TRACKING TABLE (Track individual files processed)
-- =======================================================================================================================================

CREATE OR REPLACE TABLE FILE_PROCESS_LOG (
    file_log_id             INTEGER AUTOINCREMENT PRIMARY KEY,
    batch_id                VARCHAR(50),
    source_id               INTEGER,
    file_name               VARCHAR(500),
    file_size_bytes         NUMBER(20,0),
    file_row_count          INTEGER,
    file_last_modified      TIMESTAMP,
    process_status          VARCHAR(20),        -- SUCCESS | FAILED | SKIPPED
    process_timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    error_details           VARCHAR(5000),
    FOREIGN KEY (batch_id) REFERENCES RAW_PHI.BATCH_RUN_LOG(batch_id),
    FOREIGN KEY (source_id) REFERENCES RAW_PHI.SOURCE_FILE_CONFIG(source_id)
);

CREATE OR REPLACE SEQUENCE ISOMETRICS_DEV.RAW_PHI.FILE_LOG_ID START 1 INCREMENT 1;

-- =======================================================================================================================================
-- METADATA CONFIGURATION FOR RAW_PHI TABLES
-- =======================================================================================================================================

USE DATABASE ISOMETRICS_DEV;
USE SCHEMA RAW_PHI;

-- =======================================================================================================================================
-- STEP 1: INSERT FILE FORMAT MASTER
-- =======================================================================================================================================
INSERT INTO FILE_FORMAT_MASTER
SELECT
    1,
    'CSV_FILE_FORMAT',
    'CSV',
    'GZIP',
    'UTF8',
    '.csv',
    OBJECT_CONSTRUCT(
        'FIELD_DELIMITER', ',',
        'RECORD_DELIMITER', '\n',
        'SKIP_HEADER', 1,
        'FIELD_OPTIONALLY_ENCLOSED_BY', '"',
        'TRIM_SPACE', TRUE,
        'NULL_IF', ARRAY_CONSTRUCT('NULL', ''),
        'ERROR_ON_COLUMN_COUNT_MISMATCH', FALSE,
        'EMPTY_FIELD_AS_NULL', TRUE,
        'SKIP_BYTE_ORDER_MARK', TRUE
    ),
    TRUE,
    NULL,
    CURRENT_TIMESTAMP(),
    NULL
UNION ALL
SELECT
    2,
    'JSON_FILE_FORMAT',
    'JSON',
    NULL,
    NULL,
    '.json',
    OBJECT_CONSTRUCT(
        'STRIP_OUTER_ARRAY', TRUE,
        'IGNORE_UTF8_ERRORS', FALSE,
        'REPLACE_INVALID_CHARACTERS', TRUE
    ),
    TRUE,
    NULL,
    CURRENT_TIMESTAMP(),
    NULL
UNION ALL
SELECT
    3,
    'PARQUET_FILE_FORMAT',
    'PARQUET',
    'SNAPPY',
    NULL,
    '.parquet',
    OBJECT_CONSTRUCT(
        'USE_LOGICAL_TYPE', TRUE,
        'TRIM_SPACE', FALSE
    ),
    TRUE,
    NULL,
    CURRENT_TIMESTAMP(),
    NULL;

-- =======================================================================================================================================
-- STEP 2: INSERT DATA FIELD MASTER (Business Fields)
-- =======================================================================================================================================

INSERT INTO DATA_FIELD_MASTER (field_id, field_name, data_type, length, precision, scale, nullable_flag, business_description, data_domain, pii_flag)
VALUES
-- Hospital Fields
(1, 'hospital_id', 'VARCHAR', 50, NULL, NULL, 'N', 'Unique hospital identifier', 'HOSPITAL', 'N'),
(2, 'hospital_name', 'VARCHAR', 255, NULL, NULL, 'N', 'Hospital name', 'HOSPITAL', 'N'),
(3, 'hospital_type', 'VARCHAR', 100, NULL, NULL, 'Y', 'Type of hospital', 'HOSPITAL', 'N'),
(4, 'bed_count', 'NUMBER', NULL, 10, 0, 'Y', 'Total bed capacity', 'HOSPITAL', 'N'),
(5, 'city', 'VARCHAR', 100, NULL, NULL, 'Y', 'City location', 'HOSPITAL', 'N'),
(6, 'state', 'VARCHAR', 2, NULL, NULL, 'Y', 'State code', 'HOSPITAL', 'N'),
(7, 'region', 'VARCHAR', 50, NULL, NULL, 'Y', 'Geographic region', 'HOSPITAL', 'N'),
(8, 'emr_system', 'VARCHAR', 100, NULL, NULL, 'Y', 'EMR system used', 'HOSPITAL', 'N'),
(9, 'contract_tier', 'VARCHAR', 50, NULL, NULL, 'Y', 'Contract tier level', 'HOSPITAL', 'N'),
(10, 'contract_start_date', 'TIMESTAMP_NTZ', NULL, NULL, NULL, 'Y', 'Contract start date', 'HOSPITAL', 'N'),
(11, 'is_active', 'BOOLEAN', NULL, NULL, NULL, 'Y', 'Active status flag', 'HOSPITAL', 'N'),
(12, 'teaching_hospital', 'BOOLEAN', NULL, NULL, NULL, 'Y', 'Teaching hospital flag', 'HOSPITAL', 'N'),

-- Patient Fields (PHI)
(20, 'patient_id', 'VARCHAR', 50, NULL, NULL, 'N', 'Unique patient identifier', 'PATIENT', 'Y'),
(21, 'mrn', 'VARCHAR', 100, NULL, NULL, 'Y', 'Medical Record Number', 'PATIENT', 'Y'),
(22, 'ssn_hash', 'VARCHAR', 64, NULL, NULL, 'Y', 'Hashed Social Security Number', 'PATIENT', 'Y'),
(23, 'first_name', 'VARCHAR', 100, NULL, NULL, 'Y', 'Patient first name', 'PATIENT', 'Y'),
(24, 'last_name', 'VARCHAR', 100, NULL, NULL, 'Y', 'Patient last name', 'PATIENT', 'Y'),
(25, 'date_of_birth', 'DATE', NULL, NULL, NULL, 'Y', 'Patient date of birth', 'PATIENT', 'Y'),
(26, 'gender', 'VARCHAR', 20, NULL, NULL, 'Y', 'Patient gender', 'PATIENT', 'N'),
(27, 'race', 'VARCHAR', 50, NULL, NULL, 'Y', 'Patient race', 'PATIENT', 'N'),
(28, 'ethnicity', 'VARCHAR', 100, NULL, NULL, 'Y', 'Patient ethnicity', 'PATIENT', 'N'),
(29, 'zip_code', 'VARCHAR', 10, NULL, NULL, 'Y', 'Patient ZIP code', 'PATIENT', 'Y'),
(30, 'phone_number_hash', 'VARCHAR', 64, NULL, NULL, 'Y', 'Hashed phone number', 'PATIENT', 'Y'),
(31, 'email_hash', 'VARCHAR', 64, NULL, NULL, 'Y', 'Hashed email address', 'PATIENT', 'Y'),
(32, 'primary_language', 'VARCHAR', 50, NULL, NULL, 'Y', 'Primary language', 'PATIENT', 'N'),
(33, 'marital_status', 'VARCHAR', 50, NULL, NULL, 'Y', 'Marital status', 'PATIENT', 'N'),
(34, 'first_encounter_date', 'TIMESTAMP_NTZ', NULL, NULL, NULL, 'Y', 'First encounter date', 'PATIENT', 'N'),

-- Provider Fields
(40, 'provider_id', 'VARCHAR', 50, NULL, NULL, 'N', 'Unique provider identifier', 'PROVIDER', 'N'),
(41, 'npi', 'VARCHAR', 10, NULL, NULL, 'Y', 'National Provider Identifier', 'PROVIDER', 'N'),
(42, 'provider_first_name', 'VARCHAR', 100, NULL, NULL, 'Y', 'Provider first name', 'PROVIDER', 'N'),
(43, 'provider_last_name', 'VARCHAR', 100, NULL, NULL, 'Y', 'Provider last name', 'PROVIDER', 'N'),
(44, 'specialty', 'VARCHAR', 100, NULL, NULL, 'Y', 'Medical specialty', 'PROVIDER', 'N'),
(45, 'department', 'VARCHAR', 100, NULL, NULL, 'Y', 'Department', 'PROVIDER', 'N'),
(46, 'provider_type', 'VARCHAR', 10, NULL, NULL, 'Y', 'Provider type (MD, DO, NP, PA)', 'PROVIDER', 'N'),
(47, 'hire_date', 'DATE', NULL, NULL, NULL, 'Y', 'Hire date', 'PROVIDER', 'N'),
(48, 'accepts_new_patients', 'BOOLEAN', NULL, NULL, NULL, 'Y', 'Accepts new patients flag', 'PROVIDER', 'N'),

-- Facility Fields
(50, 'facility_id', 'VARCHAR', 50, NULL, NULL, 'N', 'Unique facility identifier', 'FACILITY', 'N'),
(51, 'facility_name', 'VARCHAR', 255, NULL, NULL, 'Y', 'Facility name', 'FACILITY', 'N'),
(52, 'facility_type', 'VARCHAR', 100, NULL, NULL, 'Y', 'Facility type', 'FACILITY', 'N'),
(53, 'bed_capacity', 'NUMBER', NULL, 10, 0, 'Y', 'Bed capacity', 'FACILITY', 'N'),
(54, 'opened_date', 'TIMESTAMP_NTZ', NULL, NULL, NULL, 'Y', 'Facility opened date', 'FACILITY', 'N'),

-- Diagnosis Fields
(60, 'diagnosis_code', 'VARCHAR', 20, NULL, NULL, 'N', 'ICD-10 diagnosis code', 'DIAGNOSIS', 'N'),
(61, 'diagnosis_description', 'VARCHAR', 500, NULL, NULL, 'Y', 'Diagnosis description', 'DIAGNOSIS', 'N'),
(62, 'diagnosis_category', 'VARCHAR', 100, NULL, NULL, 'Y', 'Diagnosis category', 'DIAGNOSIS', 'N'),
(63, 'severity_level', 'VARCHAR', 50, NULL, NULL, 'Y', 'Severity level', 'DIAGNOSIS', 'N'),
(64, 'is_chronic', 'BOOLEAN', NULL, NULL, NULL, 'Y', 'Chronic condition flag', 'DIAGNOSIS', 'N'),

-- Procedure Fields
(70, 'procedure_code', 'VARCHAR', 20, NULL, NULL, 'N', 'CPT procedure code', 'PROCEDURE', 'N'),
(71, 'procedure_description', 'VARCHAR', 500, NULL, NULL, 'Y', 'Procedure description', 'PROCEDURE', 'N'),
(72, 'procedure_category', 'VARCHAR', 100, NULL, NULL, 'Y', 'Procedure category', 'PROCEDURE', 'N'),
(73, 'typical_charge_min', 'NUMBER', NULL, 10, 2, 'Y', 'Minimum typical charge', 'PROCEDURE', 'N'),
(74, 'typical_charge_max', 'NUMBER', NULL, 10, 2, 'Y', 'Maximum typical charge', 'PROCEDURE', 'N'),

-- Payer Fields
(80, 'payer_id', 'VARCHAR', 50, NULL, NULL, 'N', 'Unique payer identifier', 'PAYER', 'N'),
(81, 'payer_name', 'VARCHAR', 255, NULL, NULL, 'Y', 'Payer name', 'PAYER', 'N'),
(82, 'payer_type', 'VARCHAR', 50, NULL, NULL, 'Y', 'Payer type', 'PAYER', 'N'),
(83, 'reimbursement_rate', 'NUMBER', NULL, 5, 4, 'Y', 'Reimbursement rate', 'PAYER', 'N'),

-- Encounter Fields
(90, 'encounter_id', 'VARCHAR', 50, NULL, NULL, 'N', 'Unique encounter identifier', 'ENCOUNTER', 'Y'),
(91, 'admission_date', 'TIMESTAMP_NTZ', NULL, NULL, NULL, 'N', 'Admission date', 'ENCOUNTER', 'N'),
(92, 'discharge_date', 'TIMESTAMP_NTZ', NULL, NULL, NULL, 'Y', 'Discharge date', 'ENCOUNTER', 'N'),
(93, 'length_of_stay', 'NUMBER', NULL, 10, 2, 'Y', 'Length of stay in days', 'ENCOUNTER', 'N'),
(94, 'encounter_type', 'VARCHAR', 50, NULL, NULL, 'Y', 'Type of encounter', 'ENCOUNTER', 'N'),
(95, 'admission_source', 'VARCHAR', 100, NULL, NULL, 'Y', 'Admission source', 'ENCOUNTER', 'N'),
(96, 'discharge_disposition', 'VARCHAR', 100, NULL, NULL, 'Y', 'Discharge disposition', 'ENCOUNTER', 'N'),
(97, 'primary_diagnosis_code', 'VARCHAR', 20, NULL, NULL, 'Y', 'Primary diagnosis code', 'ENCOUNTER', 'N'),
(98, 'total_charges', 'NUMBER', NULL, 12, 2, 'Y', 'Total charges', 'ENCOUNTER', 'N'),
(99, 'is_readmission', 'BOOLEAN', NULL, NULL, NULL, 'Y', 'Readmission flag', 'ENCOUNTER', 'N'),

-- Billing Fields
(110, 'transaction_id', 'VARCHAR', 50, NULL, NULL, 'N', 'Unique transaction identifier', 'BILLING', 'N'),
(111, 'transaction_date', 'TIMESTAMP_NTZ', NULL, NULL, NULL, 'Y', 'Transaction date', 'BILLING', 'N'),
(112, 'charge_amount', 'NUMBER', NULL, 12, 2, 'Y', 'Charge amount', 'BILLING', 'N'),
(113, 'payment_amount', 'NUMBER', NULL, 12, 2, 'Y', 'Payment amount', 'BILLING', 'N'),
(114, 'adjustment_amount', 'NUMBER', NULL, 12, 2, 'Y', 'Adjustment amount', 'BILLING', 'N'),
(115, 'denial_reason', 'VARCHAR', 255, NULL, NULL, 'Y', 'Denial reason', 'BILLING', 'N'),
(116, 'payment_status', 'VARCHAR', 50, NULL, NULL, 'Y', 'Payment status', 'BILLING', 'N'),

-- Audit Fields (Common across all tables)
(200, '_loaded_at', 'TIMESTAMP_NTZ', NULL, NULL, NULL, 'Y', 'Record load timestamp', 'AUDIT', 'N'),
(201, '_source_file', 'VARCHAR', 500, NULL, NULL, 'Y', 'Source file name', 'AUDIT', 'N'),
(202, '_source_updated_at', 'TIMESTAMP_NTZ', NULL, NULL, NULL, 'Y', 'Source system update timestamp', 'AUDIT', 'N');

-- =======================================================================================================================================
-- STEP 3: INSERT SOURCE FILE CONFIGURATIONS
-- =======================================================================================================================================

INSERT INTO SOURCE_FILE_CONFIG (source_id, source_name, source_system, file_format_id, landing_path, file_pattern, ingestion_type, schedule_cron, active_flag)
VALUES
(1, 'HOSPITALS'           , 'EMR_MASTER'       , 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'hospitals.parquet' , 'BATCH'      , '0 2 * * *'  , 'Y'),
(2, 'PATIENTS'            , 'EMR_MASTER'       , 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'patients.parquet'  , 'BATCH'      , '0 3 * * *'  , 'Y'),
(3, 'PROVIDERS'           , 'EMR_MASTER'       , 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'providers.parquet' , 'BATCH'      , '0 2 * * *'  , 'Y'),
(4, 'FACILITIES'          , 'EMR_MASTER'       , 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'facilities.parquet', 'BATCH'      , '0 2 * * *'  , 'Y'),
(5, 'DIAGNOSES'           , 'REFERENCE_DATA'   , 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'diagnoses.parquet' , 'BATCH'      , '0 1 * * 0'  , 'Y'),
(6, 'PROCEDURES'          , 'REFERENCE_DATA'   , 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'procedures.parquet', 'BATCH'      , '0 1 * * 0'  , 'Y'),
(7, 'PAYERS'              , 'REFERENCE_DATA'   , 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'payers.parquet'    , 'BATCH'      , '0 1 * * 0'  , 'Y'),
(8, 'ENCOUNTERS'          , 'EMR_TRANSACTIONAL', 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'encounters.parquet', 'INCREMENTAL', '0 */4 * * *', 'Y'),
(9, 'BILLING_TRANSACTIONS', 'BILLING_SYSTEM'   , 3, '@RAW_PHI.HEALTHCARE_DATA_STAGE/', 'billing_transactions.parquet'   , 'INCREMENTAL', '0 */6 * * *', 'Y');

-- =======================================================================================================================================
-- STEP 3: INSERT FILE COLUMN MAPPINGS
-- =======================================================================================================================================

-- HOSPITALS
INSERT INTO FILE_COLUMN_MAPPING (mapping_id, source_id, file_column_name, field_id, column_position, is_primary_key, auto_increment_flag, transformation_rule, default_value, validation_rule, active_flag)
VALUES
(1001, 1, 'hospital_id'        , 1, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(1002, 1, 'hospital_name'      , 2, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1003, 1, 'hospital_type'      , 3, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1004, 1, 'bed_count'          , 4, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1005, 1, 'city'               , 5, 5, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1006, 1, 'state'              , 6, 6, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1007, 1, 'region'             , 7, 7, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1008, 1, 'emr_system'         , 8, 8, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1009, 1, 'contract_tier'      , 9, 9, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1010, 1, 'contract_start_date', 10, 10, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1011, 1, 'is_active'          , 11, 11, FALSE, FALSE, NULL, 'TRUE', NULL, 'Y'),
(1012, 1, 'teaching_hospital'  , 12, 12, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(1013, 1, '_loaded_at'         , 200, 13, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),
(1014, 1, '_source_file'       , 201, 14, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y'),

-- PATIENTS
(2001, 2, 'patient_id', 20, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(2002, 2, 'hospital_id', 1, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2003, 2, 'mrn', 21, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2004, 2, 'ssn_hash', 22, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2005, 2, 'first_name', 23, 5, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2006, 2, 'last_name', 24, 6, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2007, 2, 'date_of_birth', 25, 7, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2008, 2, 'gender', 26, 8, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2009, 2, 'race', 27, 9, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2010, 2, 'ethnicity', 28, 10, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2011, 2, 'zip_code', 29, 11, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2012, 2, 'phone_number_hash', 30, 12, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2013, 2, 'email_hash', 31, 13, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2014, 2, 'primary_language', 32, 14, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2015, 2, 'marital_status', 33, 15, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2016, 2, 'first_encounter_date', 34, 16, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(2017, 2, '_loaded_at', 200, 17, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),
(2018, 2, '_source_file', 201, 18, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y'),

-- PROVIDERS
(3001, 3, 'provider_id', 40, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(3002, 3, 'hospital_id', 1, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3003, 3, 'npi', 41, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3004, 3, 'provider_first_name', 42, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3005, 3, 'provider_last_name', 43, 5, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3006, 3, 'specialty', 44, 6, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3007, 3, 'department', 45, 7, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3008, 3, 'provider_type', 46, 8, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3009, 3, 'hire_date', 47, 9, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3010, 3, 'is_active', 11, 10, FALSE, FALSE, NULL, 'TRUE', NULL, 'Y'),
(3011, 3, 'accepts_new_patients', 48, 11, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(3012, 3, '_loaded_at', 200, 12, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),
(3013, 3, '_source_file', 201, 13, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y'),

-- FACILITIES
(4001, 4, 'facility_id', 50, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(4002, 4, 'hospital_id', 1, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(4003, 4, 'facility_name', 51, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(4004, 4, 'facility_type', 52, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(4005, 4, 'bed_capacity', 53, 5, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(4006, 4, 'is_active', 11, 6, FALSE, FALSE, NULL, 'TRUE', NULL, 'Y'),
(4007, 4, 'opened_date', 54, 7, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(4008, 4, '_loaded_at', 200, 8, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),
(4009, 4, '_source_file', 201, 9, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y'),

-- DIAGNOSES
(5001, 5, 'diagnosis_code', 60, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(5002, 5, 'diagnosis_description', 61, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(5003, 5, 'category', 62, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(5004, 5, 'severity_level', 63, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(5005, 5, 'is_chronic', 64, 5, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(5006, 5, '_source_file', 201, 9, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y'),
(5007, 5, '_loaded_at', 200, 6, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),

-- PROCEDURES
(6001, 6, 'procedure_code', 70, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(6002, 6, 'procedure_description', 71, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(6003, 6, 'category', 72, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(6004, 6, 'typical_charge_min', 73, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(6005, 6, 'typical_charge_max', 74, 5, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(6006, 5, '_source_file', 201, 9, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y'),
(6007, 6, '_loaded_at', 200, 6, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),

-- PAYERS
(7001, 7, 'payer_id', 80, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(7002, 7, 'payer_name', 81, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(7003, 7, 'payer_type', 82, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(7004, 7, 'reimbursement_rate', 83, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(7005, 7, 'is_active', 11, 5, FALSE, FALSE, NULL, 'TRUE', NULL, 'Y'),
(7006, 5, '_source_file', 201, 9, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y'),
(7007, 7, '_loaded_at', 200, 6, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),

-- ENCOUNTERS
(8001, 8, 'encounter_id', 90, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(8002, 8, 'hospital_id', 1, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8003, 8, 'patient_id', 20, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8004, 8, 'provider_id', 40, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8005, 8, 'facility_id', 50, 5, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8006, 8, 'admission_date', 91, 6, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8007, 8, 'discharge_date', 92, 7, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8008, 8, 'length_of_stay', 93, 8, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8009, 8, 'encounter_type', 94, 9, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8010, 8, 'admission_source', 95, 10, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8011, 8, 'discharge_disposition', 96, 11, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8012, 8, 'primary_diagnosis_code', 97, 12, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8013, 8, 'total_charges', 98, 13, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(8014, 8, 'is_readmission', 99, 14, FALSE, FALSE, NULL, 'FALSE', NULL, 'Y'),
(8015, 8, '_loaded_at', 200, 15, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),
(8016, 8, '_source_file', 201, 16, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y'),
(8017, 8, '_source_updated_at', 202, 17, FALSE, FALSE, NULL, NULL, NULL, 'Y'),

-- BILLING_TRANSACTIONS
(9001, 9, 'transaction_id', 110, 1, TRUE, FALSE, NULL, NULL, NULL, 'Y'),
(9002, 9, 'hospital_id', 1, 2, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9003, 9, 'encounter_id', 90, 3, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9004, 9, 'patient_id', 20, 4, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9005, 9, 'payer_id', 80, 5, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9006, 9, 'transaction_date', 111, 6, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9007, 9, 'charge_amount', 112, 7, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9008, 9, 'payment_amount', 113, 8, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9009, 9, 'adjustment_amount', 114, 9, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9010, 9, 'denial_reason', 115, 10, FALSE,FALSE, NULL, NULL, NULL, 'Y'),
(9011, 9, 'payment_status', 116, 11, FALSE, FALSE, NULL, NULL, NULL, 'Y'),
(9012, 9, '_loaded_at', 200, 12, FALSE, FALSE, 'CURRENT_TIMESTAMP()', NULL, NULL, 'Y'),
(9013, 9, '_source_file', 201, 13, FALSE, FALSE, 'METADATA$FILENAME', NULL, NULL, 'Y');

-- =======================================================================================================================================
-- STEP 4: INSERT RAW TABLE MAPPINGS
-- =======================================================================================================================================

INSERT INTO RAW_PHI.RAW_TABLE_MAPPING (target_id, source_id, raw_table, load_error_table, load_type, primary_key_fields, partition_columns, clustering_columns, merge_key_fields, enable_raw_columns, enable_audit_columns, active_flag)
VALUES
(1, 1, 'RAW_PHI.RAW_HOSPITALS', 'RAW_PHI.RAW_HOSPITALS_ERROR', 'MERGE', 'hospital_id', NULL, 'hospital_id', 'hospital_id', 'Y', 'Y', 'Y'), -- Hospitals (Reference Data - MERGE)
(2, 2, 'RAW_PHI.RAW_PATIENTS', 'RAW_PHI.RAW_PATIENTS_ERROR', 'MERGE', 'patient_id', NULL, 'hospital_id,patient_id', 'patient_id', 'Y', 'Y', 'Y'), -- Patients (Transactional PHI - MERGE)
(3, 3, 'RAW_PHI.RAW_PROVIDERS', 'RAW_PHI.RAW_PROVIDERS_ERROR', 'MERGE', 'provider_id', NULL, 'hospital_id,provider_id', 'provider_id', 'Y', 'Y', 'Y'), -- Providers (Reference Data - MERGE)
(4, 4, 'RAW_PHI.RAW_FACILITIES', 'RAW_PHI.RAW_FACILITIES_ERROR', 'MERGE', 'facility_id', NULL, 'hospital_id,facility_id', 'facility_id', 'Y', 'Y', 'Y'), -- Facilities (Reference Data - MERGE)
(5, 5, 'RAW_PHI.RAW_DIAGNOSES', 'RAW_PHI.RAW_DIAGNOSES_ERROR', 'FULL_REFRESH', 'diagnosis_code', NULL, 'diagnosis_code', NULL, 'Y', 'Y', 'Y'), -- Diagnoses (Lookup Table - FULL_REFRESH)
(6, 6, 'RAW_PHI.RAW_PROCEDURES','RAW_PHI.RAW_PROCEDURES_ERROR', 'FULL_REFRESH', 'procedure_code', NULL, 'procedure_code', NULL, 'Y', 'Y', 'Y'), -- Procedures (Lookup Table - FULL_REFRESH)
(7, 7, 'RAW_PHI.RAW_PAYERS', 'RAW_PHI.RAW_PAYERS_ERROR', 'FULL_REFRESH', 'payer_id', NULL, 'payer_id', NULL, 'Y', 'Y', 'Y'), -- Payers (Lookup Table - FULL_REFRESH)
(8, 8, 'RAW_PHI.RAW_ENCOUNTERS', 'RAW_PHI.RAW_ENCOUNTERS_ERROR', 'MERGE', 'encounter_id', 'admission_date', 'hospital_id,admission_date', 'encounter_id', 'Y', 'Y', 'Y'), -- Encounters (High Volume Transactional - APPEND with Clustering)
(9, 9, 'RAW_PHI.RAW_BILLING_TRANSACTIONS', 'RAW_PHI.RAW_BILLING_TRANSACTIONS_ERROR', 'MERGE', 'transaction_id', 'transaction_date', 'hospital_id,transaction_date', 'transaction_id', 'Y', 'Y', 'Y'); -- Billing Transactions (High Volume Transactional - APPEND with Clustering)

-- =======================================================================================================================================
-- BATCH TRACKING TABLE
-- =======================================================================================================================================
CREATE OR REPLACE TABLE BATCH_RUN_LOG (
    batch_id            VARCHAR(50) PRIMARY KEY,
    batch_run_date          DATE,
    batch_run_timestamp     TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    source_id               INTEGER,
    source_name             VARCHAR(100),
    raw_table               VARCHAR(100),
    load_type               VARCHAR(20),
    batch_status            VARCHAR(20),        -- STARTED | SUCCESS | FAILED | PARTIAL
    records_read            INTEGER,
    records_inserted        INTEGER,
    records_updated         INTEGER,
    records_deleted         INTEGER,
    records_error           INTEGER,
    files_processed         INTEGER,
    file_names              VARCHAR(5000),
    start_time              TIMESTAMP,
    end_time                TIMESTAMP,
    duration_seconds        NUMBER(10,2),
    error_message           VARCHAR(5000),
    created_by              VARCHAR(100) DEFAULT CURRENT_USER(),
    FOREIGN KEY (source_id) REFERENCES RAW_PHI.SOURCE_FILE_CONFIG(source_id)
);

stop;
-- =======================================================================================================================================
-- RAW INGESTION PROCEDURE - SINGLE SOURCE
-- =======================================================================================================================================

CREATE OR REPLACE PROCEDURE RAW_PHI.SP_LOAD_RAW_TABLE(
    P_SOURCE_ID INTEGER,
    P_BATCH_RUN_DATE DATE DEFAULT CURRENT_DATE()
)
RETURNS VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    -- Config variables
    v_source_name VARCHAR(100);
    v_landing_path VARCHAR(500);
    v_file_pattern VARCHAR(100);
    v_format_type VARCHAR(20);
    v_format_options VARIANT;
    v_compression VARCHAR(20);
    v_encoding VARCHAR(20);
    v_raw_table VARCHAR(100);
    v_error_table VARCHAR(100);
    v_load_type VARCHAR(20);
    v_primary_key VARCHAR(200);
    v_merge_key VARCHAR(200);
    v_clustering_cols VARCHAR(200);

    -- Dynamic SQL variables
    v_temp_format_name VARCHAR(100);
    v_file_format_sql STRING;
    v_copy_sql STRING;
    v_merge_sql STRING;
    v_column_list STRING;
    v_select_clause STRING;
    v_merge_condition STRING;
    v_update_clause STRING;

    -- Batch tracking variables
    v_batch_id VARCHAR(50);
    v_start_time TIMESTAMP;
    v_end_time TIMESTAMP;
    v_records_inserted INTEGER DEFAULT  0;
    v_records_updated INTEGER DEFAULT 0;
    v_files_processed INTEGER DEFAULT 0;
    v_error_message STRING DEFAULT NULL;
    v_status VARCHAR(20) DEFAULT 'STARTED';

    -- File tracking
    v_file_list STRING;

    -- Temp staging table
    v_temp_table VARCHAR(100);

BEGIN
    v_start_time := CURRENT_TIMESTAMP();
    v_batch_id := UUID_STRING();

    -- ====================================================================================================
    -- STEP 1: Fetch Configuration from Metadata
    -- ====================================================================================================

    SELECT
        sfc.source_name,
        sfc.landing_path,
        sfc.file_pattern,
        ffm.format_type,
        ffm.format_options,
        ffm.compression,
        ffm.encoding,
        rtm.raw_table,
        rtm.load_error_table,
        rtm.load_type,
        rtm.primary_key_fields,
        rtm.merge_key_fields,
        rtm.clustering_columns
    INTO
        v_source_name,
        v_landing_path,
        v_file_pattern,
        v_format_type,
        v_format_options,
        v_compression,
        v_encoding,
        v_raw_table,
        v_error_table,
        v_load_type,
        v_primary_key,
        v_merge_key,
        v_clustering_cols
    FROM RAW_PHI.SOURCE_FILE_CONFIG sfc
    JOIN RAW_PHI.FILE_FORMAT_MASTER ffm ON sfc.file_format_id = ffm.file_format_id
    JOIN RAW_PHI.RAW_TABLE_MAPPING rtm ON sfc.source_id = rtm.source_id
    WHERE sfc.source_id = :P_SOURCE_ID
      AND sfc.active_flag = 'Y'
      AND rtm.active_flag = 'Y';

    -- ====================================================================================================
    -- STEP 2: Initialize Batch Run Log
    -- ====================================================================================================

    INSERT INTO RAW_PHI.BATCH_RUN_LOG (
        batch_id,
        batch_run_date,
        source_id,
        source_name,
        raw_table,
        load_type,
        batch_status,
        start_time
    )
    VALUES (
        :v_batch_id,
        :P_BATCH_RUN_DATE,
        :P_SOURCE_ID,
        :v_source_name,
        :v_raw_table,
        :v_load_type,
        'STARTED',
        :v_start_time
    );

    -- ====================================================================================================
    -- STEP 3: Build Column List and Select Clause from FILE_COLUMN_MAPPING
    -- ====================================================================================================

    SELECT
        LISTAGG(dfm.field_name || ' ' || dfm.data_type ||
            CASE
                WHEN dfm.data_type IN ('VARCHAR', 'STRING') THEN '(' || COALESCE(dfm.length, 500) || ')'
                WHEN dfm.data_type = 'NUMBER' THEN '(' || dfm.precision || ',' || dfm.scale || ')'
                ELSE ''
            END, ', ') WITHIN GROUP (ORDER BY fcm.column_position),
        LISTAGG(
            CASE
                WHEN fcm.transformation_rule IS NOT NULL THEN fcm.transformation_rule
                WHEN fcm.default_value IS NOT NULL THEN fcm.default_value
                ELSE '$1:' || fcm.file_column_name || '::' || dfm.data_type ||
                    CASE
                        WHEN dfm.data_type IN ('VARCHAR', 'STRING') THEN '(' || COALESCE(dfm.length, 500) || ')'
                        WHEN dfm.data_type = 'NUMBER' THEN '(' || dfm.precision || ',' || dfm.scale || ')'
                        ELSE ''
                    END
            END || ' AS ' || dfm.field_name,
            ', '
        ) WITHIN GROUP (ORDER BY fcm.column_position)
    INTO v_column_list, v_select_clause
    FROM RAW_PHI.FILE_COLUMN_MAPPING fcm
    JOIN RAW_PHI.DATA_FIELD_MASTER dfm ON fcm.field_id = dfm.field_id
    WHERE fcm.source_id = :P_SOURCE_ID
      AND fcm.active_flag = 'Y'
      AND dfm.field_name NOT IN ('_source_file', '_loaded_at');

    -- ====================================================================================================
    -- STEP 4: Create Temporary Staging Table
    -- ====================================================================================================

    v_temp_table := 'RAW_PHI.TEMP_STAGE_' || v_source_name ;

    EXECUTE IMMEDIATE 'CREATE OR REPLACE TEMPORARY TABLE ' || v_temp_table || ' (' || v_column_list || ')';

    -- ====================================================================================================
    -- STEP 5: Create/Update File Format
    -- ====================================================================================================

    v_temp_format_name := 'RAW_PHI.TEMP_FORMAT_' || P_SOURCE_ID;

    v_file_format_sql := 'CREATE OR REPLACE FILE FORMAT ' || v_temp_format_name ||
                         ' TYPE = ' || CHR(39) || v_format_type || CHR(39);

    IF (v_compression IS NOT NULL) THEN
        v_file_format_sql := v_file_format_sql || ' COMPRESSION = ' || CHR(39) || v_compression || CHR(39);
    END IF;

    IF (v_encoding IS NOT NULL) THEN
        v_file_format_sql := v_file_format_sql || ' ENCODING = ' || CHR(39) || v_encoding || CHR(39);
    END IF;

    -- Add format-specific options
    IF (v_format_type = 'CSV') THEN
        v_file_format_sql := v_file_format_sql ||
            ' FIELD_DELIMITER = ' || CHR(39) || v_format_options:FIELD_DELIMITER::STRING || CHR(39) ||
            ' SKIP_HEADER = ' || v_format_options:SKIP_HEADER::INTEGER ||
            ' FIELD_OPTIONALLY_ENCLOSED_BY = ' || CHR(39) || v_format_options:FIELD_OPTIONALLY_ENCLOSED_BY::STRING || CHR(39) ||
            ' TRIM_SPACE = ' || v_format_options:TRIM_SPACE::BOOLEAN ||
            ' ERROR_ON_COLUMN_COUNT_MISMATCH = ' || v_format_options:ERROR_ON_COLUMN_COUNT_MISMATCH::BOOLEAN ||
            ' EMPTY_FIELD_AS_NULL = ' || v_format_options:EMPTY_FIELD_AS_NULL::BOOLEAN ||
            ' NULL_IF = (' || CHR(39) || 'NULL' || CHR(39) || ', ' || CHR(39) || CHR(39) || ')';
    ELSEIF (v_format_type = 'JSON') THEN
        v_file_format_sql := v_file_format_sql ||
            ' STRIP_OUTER_ARRAY = ' || v_format_options:STRIP_OUTER_ARRAY::BOOLEAN;
    ELSEIF (v_format_type = 'PARQUET') THEN
        v_file_format_sql := v_file_format_sql ||
            ' COMPRESSION = SNAPPY';
    END IF;

    EXECUTE IMMEDIATE v_file_format_sql;

    -- ====================================================================================================
    -- STEP 6: Load Data into Temporary Staging Table
    -- ====================================================================================================

    -- Add metadata columns to temp table
    EXECUTE IMMEDIATE 'ALTER TABLE ' || v_temp_table || ' ADD COLUMN _source_file VARCHAR(500)';
    EXECUTE IMMEDIATE 'ALTER TABLE ' || v_temp_table || ' ADD COLUMN _loaded_at TIMESTAMP';

    -- Add metadata to select clause
    v_select_clause := v_select_clause || ', METADATA$FILENAME AS _source_file, CURRENT_TIMESTAMP() AS _loaded_at';

    -- Build and execute COPY INTO command
    v_copy_sql := 'COPY INTO ' || v_temp_table ||
                  ' FROM (SELECT ' || v_select_clause ||
                  ' FROM ' || v_landing_path || v_file_pattern || ')' ||
                  ' FILE_FORMAT = (FORMAT_NAME = ' || CHR(39) || v_temp_format_name || CHR(39) || ')' ||
                  ' ON_ERROR = ' || CHR(39) || 'CONTINUE' || CHR(39) ||
                  ' FORCE = TRUE';

    EXECUTE IMMEDIATE v_copy_sql;

    -- -- Query temp table to get file-level statistics
    -- LET file_stats_sql STRING := 'SELECT _source_file AS file_name, COUNT(*) AS row_count ' ||
    --                               'FROM ' || v_temp_table || ' ' ||
    --                               'GROUP BY _source_file';

    -- LET file_stats RESULTSET := (EXECUTE IMMEDIATE :file_stats_sql);

    -- -- Process each file from temp table
    -- LET c_files CURSOR FOR file_stats;
    -- FOR rec IN c_files DO
    --     v_files_processed := v_files_processed + 1;
    --     v_records_inserted := v_records_inserted + rec.ROW_COUNT;

    --     -- Log each file processed
    --     INSERT INTO RAW_PHI.FILE_PROCESS_LOG (
    --         batch_id,
    --         source_id,
    --         file_name,
    --         file_row_count,
    --         process_status,
    --         process_timestamp
    --     )
    --     VALUES (
    --         :v_batch_id,
    --         :P_SOURCE_ID,
    --         rec.file_name,
    --         rec.ROW_COUNT,
    --         'LOADED',
    --         CURRENT_TIMESTAMP()
    --     );

    -- END FOR;

    -- -- Validate at least one file loaded successfully
    -- IF (v_files_processed = 0) THEN
    --     v_status := 'FAILED';
    --     v_error_message := 'No files successfully loaded for source_id: ' || P_SOURCE_ID;
    -- END IF;

    -- ====================================================================================================
    -- STEP 7: Apply Load Type Logic
    -- ====================================================================================================

    IF (v_load_type = 'FULL_REFRESH') THEN
        -- Truncate and reload
        EXECUTE IMMEDIATE 'TRUNCATE TABLE ' || v_raw_table;
        EXECUTE IMMEDIATE 'INSERT INTO ' || v_raw_table || ' SELECT * FROM ' || v_temp_table;
        v_status := 'SUCCESS';

    ELSEIF (v_load_type = 'APPEND') THEN
        -- Simple append
        EXECUTE IMMEDIATE 'INSERT INTO ' || v_raw_table || ' SELECT * FROM ' || v_temp_table;
        v_status := 'SUCCESS';

    ELSEIF (v_load_type = 'MERGE') THEN
        -- Build MERGE statement
        v_merge_condition := '';
        LET key_array ARRAY := SPLIT(v_merge_key, ',');
        FOR i IN 0 TO ARRAY_SIZE(key_array) - 1 DO
            IF (i > 0) THEN
                v_merge_condition := v_merge_condition || ' AND ';
            END IF;
            v_merge_condition := v_merge_condition || 'TGT.' || TRIM(key_array[i]) || ' = SRC.' || TRIM(key_array[i]);
        END FOR;

        -- Build UPDATE clause (all columns except PK and audit columns)
        SELECT
            LISTAGG('TGT.' || dfm.field_name || ' = SRC.' || dfm.field_name, ', ')
                WITHIN GROUP (ORDER BY fcm.column_position)
        INTO v_update_clause
        FROM RAW_PHI.FILE_COLUMN_MAPPING fcm
        JOIN RAW_PHI.DATA_FIELD_MASTER dfm ON fcm.field_id = dfm.field_id
        WHERE fcm.source_id = :P_SOURCE_ID
            AND fcm.is_primary_key = FALSE
            AND dfm.field_name NOT IN ('_source_file', '_loaded_at')
            AND fcm.active_flag = 'Y';

        -- Build column lists for MERGE
        LET insert_cols STRING;
        LET insert_vals STRING;

        SELECT
            LISTAGG(dfm.field_name, ', ') WITHIN GROUP (ORDER BY fcm.column_position),
            LISTAGG('SRC.' || dfm.field_name, ', ') WITHIN GROUP (ORDER BY fcm.column_position)
        INTO insert_cols, insert_vals
        FROM RAW_PHI.FILE_COLUMN_MAPPING fcm
        JOIN RAW_PHI.DATA_FIELD_MASTER dfm ON fcm.field_id = dfm.field_id
        WHERE fcm.source_id = :P_SOURCE_ID
            AND fcm.active_flag = 'Y'
            AND dfm.field_name NOT IN ('_source_file', '_loaded_at');

        -- Get counts before merge
        LET pre_merge_count INTEGER;
        LET count_sql STRING := 'SELECT COUNT(*) AS cnt FROM ' || v_raw_table;
        LET count_result RESULTSET := (EXECUTE IMMEDIATE :count_sql);
        LET c_pre CURSOR FOR count_result;
        FOR r IN c_pre DO
            pre_merge_count := r.CNT;
        END FOR;

        -- Execute MERGE
        v_merge_sql :=
            'MERGE INTO ' || v_raw_table || ' TGT ' ||
            'USING ' || v_temp_table || ' SRC ' ||
            'ON ' || v_merge_condition || ' ' ||
            'WHEN MATCHED THEN UPDATE SET ' || v_update_clause || ' ' ||
            'WHEN NOT MATCHED THEN INSERT (' || insert_cols || ') ' ||
            'VALUES (' || insert_vals || ')';

        EXECUTE IMMEDIATE v_merge_sql;

        -- Get counts after merge
        LET post_merge_count INTEGER;
        count_sql := 'SELECT COUNT(*) AS cnt FROM ' || v_raw_table;
        count_result := (EXECUTE IMMEDIATE :count_sql);
        LET c_post CURSOR FOR count_result;
        FOR r IN c_post DO
            post_merge_count := r.CNT;
        END FOR;

        -- Calculate inserted and updated records
        v_records_inserted := post_merge_count - pre_merge_count;

        -- Get temp table count to calculate updates
        LET temp_count INTEGER;
        count_sql := 'SELECT COUNT(*) AS cnt FROM ' || v_temp_table;
        count_result := (EXECUTE IMMEDIATE :count_sql);
        LET c_temp CURSOR FOR count_result;
        FOR r IN c_temp DO
            temp_count := r.CNT;
        END FOR;

        v_records_updated := temp_count - v_records_inserted;

        v_status := 'SUCCESS';
    END IF;

    -- ====================================================================================================
    -- STEP 8: Apply Clustering if Configured
    -- ====================================================================================================

    IF (v_clustering_cols IS NOT NULL AND v_clustering_cols != '') THEN
        EXECUTE IMMEDIATE 'ALTER TABLE ' || v_raw_table || ' CLUSTER BY (' || v_clustering_cols || ')';
    END IF;

    -- -- ====================================================================================================
    -- -- STEP 9: Update Batch Run Log
    -- -- ====================================================================================================

    v_end_time := CURRENT_TIMESTAMP();

    -- UPDATE RAW_PHI.BATCH_RUN_LOG
    -- SET batch_status = :v_status,
    --     records_inserted = :v_records_inserted,
    --     records_updated = :v_records_updated,
    --     files_processed = :v_files_processed,
    --     end_time = :v_end_time,
    --     duration_seconds = DATEDIFF(SECOND, v_start_time, v_end_time)
    -- WHERE batch_id = :v_batch_id;

    -- Drop temp table
    EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS ' || v_temp_table;
    EXECUTE IMMEDIATE 'DROP FILE FORMAT IF EXISTS ' || v_temp_format_name;

    RETURN OBJECT_CONSTRUCT(
        'status',            'SUCCESS',
        'batch_id',          v_batch_id,
        'source_name',       v_source_name,
        'records_inserted',  v_records_inserted,
        'records_updated',   v_records_updated,
        'files_processed',   v_files_processed
    );

EXCEPTION
    WHEN OTHER THEN
        v_error_message := SQLERRM;
        v_status := 'FAILED';
        v_end_time := CURRENT_TIMESTAMP();

        UPDATE RAW_PHI.BATCH_RUN_LOG
        SET batch_status = :v_status,
            error_message = :v_error_message,
            end_time = :v_end_time,
            duration_seconds = DATEDIFF(SECOND, :v_start_time, :v_end_time)
        WHERE batch_id = :v_batch_id;

        -- Drop temp table
        EXECUTE IMMEDIATE 'DROP TABLE IF EXISTS ' || v_temp_table;

        RETURN 'FAILED: Batch ' || v_batch_id || ' - ' || SQLERRM;
END;
$$;

-- =======================================================================================================================================
-- MASTER ORCHESTRATION PROCEDURE - Process All Active Sources
-- =======================================================================================================================================

CREATE OR REPLACE PROCEDURE RAW_PHI.SP_LOAD_ALL_RAW_TABLES(
    P_BATCH_RUN_DATE DATE DEFAULT CURRENT_DATE()
)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    v_source_id INTEGER;
    v_result STRING;
    v_total_success INTEGER := 0;
    v_total_failed INTEGER := 0;
    c_sources CURSOR FOR
        SELECT source_id
        FROM RAW_PHI.SOURCE_FILE_CONFIG
        WHERE active_flag = 'Y'
        ORDER BY source_id;
BEGIN
    FOR record IN c_sources DO
        v_source_id := record.source_id;

        CALL RAW_PHI.SP_LOAD_RAW_TABLE(:v_source_id, :P_BATCH_RUN_DATE);

        -- Check if successful
        LET last_batch_status STRING := (
            SELECT batch_status
            FROM RAW_PHI.BATCH_RUN_LOG
            WHERE source_id = :v_source_id
            ORDER BY batch_id DESC
            LIMIT 1
        );

        IF (last_batch_status = 'SUCCESS') THEN
            v_total_success := v_total_success + 1;
        ELSE
            v_total_failed := v_total_failed + 1;
        END IF;
    END FOR;

    RETURN 'COMPLETED: Success=' || v_total_success || ', Failed=' || v_total_failed;
END;
$$;
-- =======================================================================================================================================