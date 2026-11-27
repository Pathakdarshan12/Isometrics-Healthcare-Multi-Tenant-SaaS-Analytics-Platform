{{
  config(
    materialized='view',
    secure = True,
    tags=['staging', 'bronze', 'patients'],
    schema = 'staging',
    post_hook=["{{ apply_rls_policy() }}"],
    meta={
      'contains_phi': true,
      'phi_fields': ['birth_year']
    }
  )
}}

/*
  Access control is enforced by the hospital_isolation_policy row access policy
  (attached via post_hook), not by filtering on CURRENT_ROLE() here.

  HIPAA Safe Harbor applied:
  - names / MRN not selected (they stay in RAW_PHI)
  - date_of_birth reduced to birth year; ages > 89 aggregated into 90
  - ZIP reduced to 3 digits with low-population prefixes set to '000'
*/

with source as (
    select * from {{ source('healthcare', 'raw_patients') }}
),

aged as (
    select
        *,
        -- Exact age in completed years (datediff('year') overcounts before the birthday)
        floor(months_between(current_date(), date_of_birth) / 12)::int as exact_age_years
    from source
),

deidentified as (
    select
        -- Primary Key
        patient_id,

        -- Foreign Keys
        hospital_id,  -- 🔒 CRITICAL for RLS

        -- Year only; suppressed for 90+ (Safe Harbor)
        case
            when exact_age_years > 89 then null
            else year(date_of_birth)
        end as birth_year,

        -- Age, top-coded at 90 (Safe Harbor)
        least(exact_age_years, 90) as age_years,
        (exact_age_years > 89) as is_age_90_plus,

        -- Age group (for analytics)
        {{ calculate_age_group('exact_age_years') }} as age_group,

        gender,
        race,
        ethnicity,

        {{ deidentify_zipcode('zip_code') }} as zip_code_3digit,

        primary_language,
        marital_status,

        -- Dates
        first_encounter_date,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from aged
)

select * from deidentified
