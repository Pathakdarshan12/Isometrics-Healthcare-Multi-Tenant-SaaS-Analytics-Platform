{{
  config(
    materialized='incremental',
    unique_key='encounter_id',
    incremental_strategy='delete+insert',
    cluster_by=['hospital_id', 'admission_date_day'],
    on_schema_change='fail',
    tags=['marts', 'incremental', 'encounters']
  )
}}

/*
  Incremental Strategy:
  - delete+insert chosen over merge for performance
  - Partitioned by hospital_id + date for efficient deletes
  - Handles late-arriving data by deleting and re-inserting affected partitions
*/

with enriched_encounters as (
    select * from {{ ref('int_encounters__enriched') }}
),

final as (
    select
        -- Keys
        encounter_id,
        hospital_id,
        patient_id,
        provider_id,
        facility_id,
        primary_diagnosis_code,

        -- Hospital Context
        hospital_name,
        hospital_type,
        region,
        teaching_hospital,

        -- Patient Demographics
        age_years,
        age_group,
        gender,
        race,
        ethnicity,

        -- Provider
        provider_full_name,
        specialty as provider_specialty,
        department as provider_department,
        provider_type,

        -- Facility
        facility_name,
        facility_type,

        -- Diagnosis
        diagnosis_description,
        diagnosis_category,
        severity_level,
        is_chronic as is_chronic_condition,

        -- Encounter Details
        encounter_type,
        admission_source,
        discharge_disposition,
        admission_date,
        discharge_date,
        length_of_stay,

        -- Date Dimensions
        admission_date_day,
        admission_date_month,
        admission_date_quarter,
        admission_date_year,
        admission_day_of_week,

        -- Financial
        total_charges,

        -- Quality Indicators
        is_readmission,
        is_mortality,
        is_emergency,
        is_transfer,

        -- Metadata
        loaded_at_timestamp,
        current_timestamp() as _dbt_updated_at

    from enriched_encounters

    {% if is_incremental() %}
        -- Incremental logic: Only process new or updated encounters
        where loaded_at_timestamp > (
            select max(loaded_at_timestamp)
            from {{ this }}
        )
    {% endif %}
)

select * from final