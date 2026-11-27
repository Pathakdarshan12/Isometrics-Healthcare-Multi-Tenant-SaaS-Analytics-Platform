{{
  config(
    materialized='incremental',
    unique_key='encounter_id',
    incremental_strategy='delete+insert',
    cluster_by=['hospital_id', 'admission_date_day'],
    on_schema_change='fail',
    tags=['marts', 'incremental', 'encounters'],
    schema = 'marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  Incremental Strategy:
  - delete+insert chosen over merge for performance
  - Clustered by hospital_id + date for efficient deletes
  - Late-arriving/updated rows are picked up via loaded_at_timestamp and
    replace the existing row with the same encounter_id
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
    -- Only process encounters loaded since the last run
    where loaded_at_timestamp > (
        select coalesce(max(loaded_at_timestamp), '1900-01-01'::timestamp_ntz)
        from {{ this }}
    )
    {% endif %}

)

select * from final