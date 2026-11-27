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

-- 10. Load Quality Measures
COPY INTO RAW_PHI.raw_quality_measures
(measure_id, hospital_id, encounter_id, patient_id, measure_code, measure_name, measure_category,
 numerator_eligible, denominator_eligible, exclusion_applied, exclusion_reason,
 door_to_antibiotic_minutes, door_to_balloon_minutes, door_to_needle_minutes,
 metric_component, component_value, component_timestamp, compliance_flag,
 reporting_quarter, reporting_year, _loaded_at)
FROM (
    SELECT
        $1:measure_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:measure_code::VARCHAR(50),
        $1:measure_name::VARCHAR(255),
        $1:measure_category::VARCHAR(100),
        $1:numerator_eligible::BOOLEAN,
        $1:denominator_eligible::BOOLEAN,
        $1:exclusion_applied::BOOLEAN,
        $1:exclusion_reason::VARCHAR(255),
        $1:door_to_antibiotic_minutes::INTEGER,
        $1:door_to_balloon_minutes::INTEGER,
        $1:door_to_needle_minutes::INTEGER,
        $1:metric_component::VARCHAR(100),
        $1:component_value::VARCHAR(500),
        $1:component_timestamp::TIMESTAMP_NTZ,
        $1:compliance_flag::BOOLEAN,
        $1:reporting_quarter::VARCHAR(10),
        $1:reporting_year::INTEGER,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/quality_measures.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 11. Load Care Plans
COPY INTO RAW_PHI.raw_care_plans
(care_plan_id, hospital_id, encounter_id, patient_id, problem_description, goal_description,
 intervention_description, plan_status, start_date, target_date, completion_date,
 created_by_provider_id, assigned_to_provider_ids, progress_notes, last_evaluated_date, _loaded_at)
FROM (
    SELECT
        $1:care_plan_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:problem_description::VARCHAR(500),
        $1:goal_description::TEXT,
        $1:intervention_description::TEXT,
        $1:plan_status::VARCHAR(50),
        $1:start_date::DATE,
        $1:target_date::DATE,
        $1:completion_date::DATE,
        $1:created_by_provider_id::VARCHAR(50),
        $1:assigned_to_provider_ids::VARCHAR(500),
        $1:progress_notes::TEXT,
        $1:last_evaluated_date::DATE,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/care_plans.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 12. Load Referrals
COPY INTO RAW_PHI.raw_referrals
(referral_id, hospital_id, patient_id, encounter_id, referral_type, referring_provider_id,
 referred_to_provider_id, referred_to_facility, specialty, referral_status, referral_date,
 appointment_date, completion_date, reason_for_referral, diagnosis_codes, urgency,
 follow_up_required, follow_up_completed, _loaded_at)
FROM (
    SELECT
        $1:referral_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:referral_type::VARCHAR(50),
        $1:referring_provider_id::VARCHAR(50),
        $1:referred_to_provider_id::VARCHAR(50),
        $1:referred_to_facility::VARCHAR(255),
        $1:specialty::VARCHAR(100),
        $1:referral_status::VARCHAR(50),
        $1:referral_date::DATE,
        $1:appointment_date::DATE,
        $1:completion_date::DATE,
        $1:reason_for_referral::TEXT,
        $1:diagnosis_codes::VARCHAR(500),
        $1:urgency::VARCHAR(50),
        $1:follow_up_required::BOOLEAN,
        $1:follow_up_completed::BOOLEAN,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/referrals.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 13. Load Prior Authorizations
COPY INTO RAW_PHI.raw_prior_authorizations
(auth_id, hospital_id, patient_id, payer_id, encounter_id, auth_number, auth_type,
 service_code, service_description, auth_status, request_date, decision_date,
 effective_date, expiration_date, units_authorized, units_used, units_remaining,
 diagnosis_codes, clinical_notes, denial_reason, _loaded_at)
FROM (
    SELECT
        $1:auth_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:payer_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:auth_number::VARCHAR(100),
        $1:auth_type::VARCHAR(50),
        $1:service_code::VARCHAR(20),
        $1:service_description::VARCHAR(500),
        $1:auth_status::VARCHAR(50),
        $1:request_date::DATE,
        $1:decision_date::DATE,
        $1:effective_date::DATE,
        $1:expiration_date::DATE,
        $1:units_authorized::INTEGER,
        $1:units_used::INTEGER,
        $1:units_remaining::INTEGER,
        $1:diagnosis_codes::VARCHAR(500),
        $1:clinical_notes::TEXT,
        $1:denial_reason::TEXT,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/prior_authorizations.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 14. Load Vital Signs
COPY INTO RAW_PHI.raw_vital_signs
(vital_id, hospital_id, encounter_id, patient_id, measurement_datetime, temperature_f, heart_rate_bpm, respiratory_rate, systolic_bp, diastolic_bp, oxygen_saturation_pct, weight_kg, height_cm, bmi, pain_score, map_mmhg, position, measured_by_role, _loaded_at)
FROM (
    SELECT
        $1:vital_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:measurement_datetime::TIMESTAMP_NTZ,
        $1:temperature_f::NUMBER(5,2),
        $1:heart_rate_bpm::INTEGER,
        $1:respiratory_rate::INTEGER,
        $1:systolic_bp::INTEGER,
        $1:diastolic_bp::INTEGER,
        $1:oxygen_saturation_pct::INTEGER,
        $1:weight_kg::NUMBER(6,2),
        $1:height_cm::NUMBER(5,1),
        $1:bmi::NUMBER(4,1),
        $1:pain_score::INTEGER,
        $1:map_mmhg::INTEGER,
        $1:position::VARCHAR(50),
        $1:measured_by_role::VARCHAR(50),
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/vital_signs.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 15. Load Clinical Orders
COPY INTO RAW_PHI.raw_clinical_orders
(order_id, hospital_id, encounter_id, patient_id, provider_id, order_type, order_code, order_description, order_status, order_datetime, scheduled_datetime, completed_datetime, priority, ordering_provider_id, performing_location, medication_name, dose, route, frequency, duration_days, specimen_type, collection_datetime, result_id, _loaded_at, _source_file)
FROM (
    SELECT
        $1:order_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:provider_id::VARCHAR(50),
        $1:order_type::VARCHAR(50),
        $1:order_code::VARCHAR(20),
        $1:order_description::VARCHAR(500),
        $1:order_status::VARCHAR(50),
        $1:order_datetime::TIMESTAMP_NTZ,
        $1:scheduled_datetime::TIMESTAMP_NTZ,
        $1:completed_datetime::TIMESTAMP_NTZ,
        $1:priority::VARCHAR(20),
        $1:ordering_provider_id::VARCHAR(50),
        $1:performing_location::VARCHAR(100),
        $1:medication_name::VARCHAR(255),
        $1:dose::VARCHAR(50),
        $1:route::VARCHAR(50),
        $1:frequency::VARCHAR(50),
        $1:duration_days::INTEGER,
        $1:specimen_type::VARCHAR(100),
        $1:collection_datetime::TIMESTAMP_NTZ,
        $1:result_id::VARCHAR(50),
        CURRENT_TIMESTAMP(),
        METADATA$FILENAME
    FROM @healthcare_data_stage/2023/clinical_orders.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 16. Load Clinical Results
COPY INTO RAW_PHI.raw_clinical_results
(result_id, hospital_id, order_id, patient_id, encounter_id, result_type, test_code, test_name, component_code, component_name, result_value, result_value_numeric, result_units, reference_range_low, reference_range_high, abnormal_flag, result_datetime, collected_datetime, resulted_datetime, result_status, performing_lab, interpreting_provider_id, imaging_modality, impression, report_text, _loaded_at)
FROM (
    SELECT
        $1:result_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:order_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:result_type::VARCHAR(50),
        $1:test_code::VARCHAR(20),
        $1:test_name::VARCHAR(255),
        $1:component_code::VARCHAR(20),
        $1:component_name::VARCHAR(255),
        $1:result_value::VARCHAR(500),
        $1:result_value_numeric::NUMBER(18,4),
        $1:result_units::VARCHAR(50),
        $1:reference_range_low::NUMBER(18,4),
        $1:reference_range_high::NUMBER(18,4),
        $1:abnormal_flag::VARCHAR(10),
        $1:result_datetime::TIMESTAMP_NTZ,
        $1:collected_datetime::TIMESTAMP_NTZ,
        $1:resulted_datetime::TIMESTAMP_NTZ,
        $1:result_status::VARCHAR(50),
        $1:performing_lab::VARCHAR(100),
        $1:interpreting_provider_id::VARCHAR(50),
        $1:imaging_modality::VARCHAR(50),
        $1:impression::VARCHAR,
        $1:report_text::VARCHAR,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/clinical_results.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 17. Load Medication Administration
COPY INTO RAW_PHI.raw_medication_administration
(admin_id, hospital_id, encounter_id, patient_id, order_id, medication_name, dose, route, scheduled_datetime, administered_datetime, administered_by_provider_id, administration_status, refusal_reason, hold_reason, barcode_scanned, witnessed_by_provider_id, adverse_reaction_flag, reaction_description, _loaded_at)
FROM (
    SELECT
        $1:admin_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:order_id::VARCHAR(50),
        $1:medication_name::VARCHAR(255),
        $1:dose::VARCHAR(50),
        $1:route::VARCHAR(50),
        $1:scheduled_datetime::TIMESTAMP_NTZ,
        $1:administered_datetime::TIMESTAMP_NTZ,
        $1:administered_by_provider_id::VARCHAR(50),
        $1:administration_status::VARCHAR(50),
        $1:refusal_reason::VARCHAR(255),
        $1:hold_reason::VARCHAR(255),
        $1:barcode_scanned::BOOLEAN,
        $1:witnessed_by_provider_id::VARCHAR(50),
        $1:adverse_reaction_flag::BOOLEAN,
        $1:reaction_description::VARCHAR,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/medication_administration.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 18. Load Patient Allergies
COPY INTO RAW_PHI.raw_patient_allergies
(allergy_id, hospital_id, patient_id, allergen_type, allergen_code, allergen_name, reaction_type, severity, allergy_status, onset_date, resolution_date, documented_by_provider_id, documentation_date, clinical_notes, _loaded_at)
FROM (
    SELECT
        $1:allergy_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:allergen_type::VARCHAR(50),
        $1:allergen_code::VARCHAR(20),
        $1:allergen_name::VARCHAR(255),
        $1:reaction_type::VARCHAR(100),
        $1:severity::VARCHAR(50),
        $1:allergy_status::VARCHAR(50),
        $1:onset_date::TIMESTAMP_NTZ::DATE,
        $1:resolution_date::TIMESTAMP_NTZ::DATE,
        $1:documented_by_provider_id::VARCHAR(50),
        $1:documentation_date::TIMESTAMP_NTZ::DATE,
        $1:clinical_notes::VARCHAR,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/patient_allergies.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 19. Load Problem List
COPY INTO RAW_PHI.raw_problem_list
(problem_id, hospital_id, patient_id, diagnosis_code, diagnosis_description, problem_status, onset_date, resolution_date, last_reviewed_date, severity, is_chronic, is_primary_diagnosis, documented_by_provider_id, documentation_date, clinical_notes, _loaded_at)
FROM (
    SELECT
        $1:problem_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:diagnosis_code::VARCHAR(20),
        $1:diagnosis_description::VARCHAR(500),
        $1:problem_status::VARCHAR(50),
        $1:onset_date::TIMESTAMP_NTZ::DATE,
        $1:resolution_date::TIMESTAMP_NTZ::DATE,
        $1:last_reviewed_date::TIMESTAMP_NTZ::DATE,
        $1:severity::VARCHAR(50),
        $1:is_chronic::BOOLEAN,
        $1:is_primary_diagnosis::BOOLEAN,
        $1:documented_by_provider_id::VARCHAR(50),
        $1:documentation_date::TIMESTAMP_NTZ::DATE,
        $1:clinical_notes::VARCHAR,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/problem_list.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 20. Load Patient Coverage
COPY INTO RAW_PHI.raw_patient_coverage
(coverage_id, hospital_id, patient_id, payer_id, policy_number, group_number, subscriber_id, subscriber_name, subscriber_relationship, effective_date, termination_date, coverage_status, plan_type, coverage_level, deductible_amount, deductible_met_amount, out_of_pocket_max, out_of_pocket_met, copay_amount, coinsurance_pct, coverage_priority, _loaded_at)
FROM (
    SELECT
        $1:coverage_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:payer_id::VARCHAR(50),
        $1:policy_number::VARCHAR(100),
        $1:group_number::VARCHAR(100),
        $1:subscriber_id::VARCHAR(100),
        $1:subscriber_name::VARCHAR(255),
        $1:subscriber_relationship::VARCHAR(50),
        $1:effective_date::TIMESTAMP_NTZ::DATE,
        $1:termination_date::TIMESTAMP_NTZ::DATE,
        $1:coverage_status::VARCHAR(50),
        $1:plan_type::VARCHAR(50),
        $1:coverage_level::VARCHAR(50),
        $1:deductible_amount::NUMBER(10,2),
        $1:deductible_met_amount::NUMBER(10,2),
        $1:out_of_pocket_max::NUMBER(10,2),
        $1:out_of_pocket_met::NUMBER(10,2),
        $1:copay_amount::NUMBER(10,2),
        $1:coinsurance_pct::NUMBER(5,2),
        $1:coverage_priority::INTEGER,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/patient_coverage.parquet
)
FILE_FORMAT = healthcare_parquet_format
ON_ERROR = 'ABORT_STATEMENT'
PURGE = FALSE;

-- 21. Load Sdoh Screenings
COPY INTO RAW_PHI.raw_sdoh_screenings
(screening_id, hospital_id, patient_id, encounter_id, screening_date, housing_status, housing_concerns, food_insecurity_flag, difficulty_affording_food, transportation_barriers, difficulty_paying_utilities, difficulty_affording_medications, social_isolation_score, safety_concerns, intimate_partner_violence_screen, employment_status, highest_education_level, health_literacy_score, screening_tool_name, referrals_text, _loaded_at)
FROM (
    SELECT
        $1:screening_id::VARCHAR(50),
        $1:hospital_id::VARCHAR(50),
        $1:patient_id::VARCHAR(50),
        $1:encounter_id::VARCHAR(50),
        $1:screening_date::TIMESTAMP_NTZ::DATE,
        $1:housing_status::VARCHAR(50),
        $1:housing_concerns::BOOLEAN,
        $1:food_insecurity_flag::BOOLEAN,
        $1:difficulty_affording_food::BOOLEAN,
        $1:transportation_barriers::BOOLEAN,
        $1:difficulty_paying_utilities::BOOLEAN,
        $1:difficulty_affording_medications::BOOLEAN,
        $1:social_isolation_score::INTEGER,
        $1:safety_concerns::BOOLEAN,
        $1:intimate_partner_violence_screen::BOOLEAN,
        $1:employment_status::VARCHAR(50),
        $1:highest_education_level::VARCHAR(50),
        $1:health_literacy_score::INTEGER,
        $1:screening_tool_name::VARCHAR(100),
        $1:referrals_text::VARCHAR,
        CURRENT_TIMESTAMP()
    FROM @healthcare_data_stage/2023/sdoh_screenings.parquet
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