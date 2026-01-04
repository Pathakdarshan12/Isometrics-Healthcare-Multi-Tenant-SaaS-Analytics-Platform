{{
  config(
    materialized='view',
    secure = True,
    tags=['staging', 'bronze', 'providers'],
    schema = 'staging',
    cluster_by=['hospital_id', 'provider_id'],
    post_hook=["{{ apply_rls_policy() }}"],
    meta={
      'contains_phi': false,
      'owner': 'healthcare-data-team@company.com'
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_providers') }}
    WHERE CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DBT_DEV_ROLE') -- Admin/Dev roles see everything
),

renamed as (
    select
        -- Primary Key
        provider_id,

        -- Foreign Keys
        hospital_id,  -- 🔒 CRITICAL for RLS

        -- Provider Identifiers
        npi,

        -- Provider Info
        provider_first_name,
        provider_last_name,
        concat(provider_first_name, ' ', provider_last_name) as provider_full_name,

        -- Practice Details
        specialty,
        department,
        provider_type,

        -- Status
        is_active,
        accepts_new_patients,

        -- Dates
        hire_date,

        -- Calculate tenure
        datediff('year', hire_date, current_date()) as years_of_service,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed