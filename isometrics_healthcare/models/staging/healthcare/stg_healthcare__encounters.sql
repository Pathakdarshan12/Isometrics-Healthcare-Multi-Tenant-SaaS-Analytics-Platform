{{
  config(
    materialized='view',
    tags=['staging', 'bronze', 'encounters'],
    meta={
      'contains_phi': true,
      'phi_fields': ['admission_date', 'discharge_date'],
      'owner': 'healthcare-data-team@company.com'
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_encounters') }}
),

cleaned as (
    select
        -- Primary Key
        encounter_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        patient_id,
        provider_id,
        facility_id,
        primary_diagnosis_code,

        -- Encounter Details
        encounter_type,
        admission_source,
        discharge_disposition,

        -- Dates
        admission_date,
        discharge_date,
        length_of_stay,

        -- Derived date parts (for analytics)
        date_trunc('day', admission_date) as admission_date_day,
        date_trunc('month', admission_date) as admission_date_month,
        date_trunc('year', admission_date) as admission_date_year,
        date_trunc('quarter', admission_date) as admission_date_quarter,

        -- Day of week
        dayname(admission_date) as admission_day_of_week,
        dayofweek(admission_date) as admission_day_of_week_num,

        -- Financial
        total_charges,

        -- Quality Indicators
        is_readmission,

        -- Flags
        case
            when discharge_disposition = 'Deceased' then true
            else false
        end as is_mortality,

        case
            when encounter_type = 'Emergency' then true
            else false
        end as is_emergency,

        case
            when admission_source = 'Transfer' then true
            else false
        end as is_transfer,

        -- Metadata
        _loaded_at as loaded_at_timestamp,
        _source_updated_at as source_updated_at_timestamp

    from source
),

validated as (
    -- Data quality: Remove invalid records
    select *
    from cleaned
    where
        -- Discharge must be after admission
        discharge_date >= admission_date
        -- Charges must be positive
        and total_charges >= 0
        -- Length of stay must be reasonable
        and length_of_stay >= 0
        and length_of_stay < 365  -- Cap at 1 year
)

select * from validated