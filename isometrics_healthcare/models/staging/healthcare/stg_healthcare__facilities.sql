{{
  config(
    materialized='view',
    tags=['staging', 'bronze', 'facilities']
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_facilities') }}
),

renamed as (
    select
        -- Primary Key
        facility_id,

        -- Foreign Keys
        hospital_id,  -- 🔒 CRITICAL for RLS

        -- Facility Details
        facility_name,
        facility_type,
        bed_capacity,

        -- Status
        is_active,

        -- Dates
        opened_date,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
    where is_active = true
)

select * from renamed