{{
  config(
    materialized='view',
    tags=['staging', 'reference', 'procedures'],
    schema = 'staging'
  )
}}

with source as (
    select * from {{ source('reference', 'raw_procedures') }}
),

renamed as (
    select
        -- Primary Key
        procedure_code,

        -- Attributes
        procedure_description,
        category,
        typical_charge_min,
        typical_charge_max,

        -- Calculate typical charge midpoint
        (typical_charge_min + typical_charge_max) / 2 as typical_charge_avg,

        -- Calculate charge range
        typical_charge_max - typical_charge_min as charge_range,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed