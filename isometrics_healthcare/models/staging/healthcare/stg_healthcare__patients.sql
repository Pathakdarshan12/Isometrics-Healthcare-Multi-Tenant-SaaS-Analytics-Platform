{{
  config(
    materialized='view',
    tags=['staging', 'bronze', 'patients'],
    meta={
      'contains_phi': true,
      'phi_fields': ['date_of_birth', 'zip_code'],
      'owner': 'healthcare-data-team@company.com'
    }
  )
}}

with source as(
    select * from {{ source('healthcare', 'raw_patients') }}
),
deidentified as (
    select
        -- Primary Key
        patient_id,

        -- Foreign Keys
        hospital_id,  -- 🔒 CRITICAL for RLS

        -- Demographics (De-identified where possible)
        -- NOTE: We're NOT selecting first_name, last_name, mrn in staging
        -- Those stay in raw layer for authorized access only

        date_of_birth,  -- Required for age calculations

        -- Calculate age (de-identified)
        datediff('year', date_of_birth, current_date()) as age_years,

        -- Age group (for analytics)
        case
            when datediff('year', date_of_birth, current_date()) < 18 then 'Pediatric'
            when datediff('year', date_of_birth, current_date()) between 18 and 64 then 'Adult'
            when datediff('year', date_of_birth, current_date()) >= 65 then 'Geriatric'
            else 'Unknown'
        end as age_group,

        gender,
        race,
        ethnicity,

        -- Zip code first 3 digits only (HIPAA Safe Harbor de-identification)
        left(zip_code, 3) as zip_code_3digit,

        primary_language,
        marital_status,

        -- Dates
        first_encounter_date,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)
select * from deidentified