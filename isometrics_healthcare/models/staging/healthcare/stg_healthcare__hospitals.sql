{{
  config(
    materialized='view',
    secure = True,
    tags=['staging', 'bronze', 'hospitals', 'tenants'],
    schema = 'staging',
    post_hook=["{{ apply_rls_policy() }}"],
    meta={
      'contains_phi': false,
      'owner': 'healthcare-data-team@company.com'
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_hospitals') }}
),

renamed as (
    select
        -- Primary Key
        hospital_id,

        -- Hospital Attributes
        hospital_name,
        hospital_type,
        bed_count,

        -- Location
        city,
        state,
        region,

        -- Systems & Contract
        emr_system,
        contract_tier,
        contract_start_date,

        -- Flags
        is_active,
        teaching_hospital,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
    where is_active = true  -- Only active hospitals
)

select * from renamed