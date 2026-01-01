{{
  config(
    materialized='view',
    tags=['staging', 'reference', 'diagnoses']
  )
}}

with source as (
    select * from {{ source('reference', 'raw_diagnoses') }}
),

renamed as (
    select
        -- Primary Key
        diagnosis_code,

        -- Attributes
        diagnosis_description,
        category,
        severity_level,
        is_chronic,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed