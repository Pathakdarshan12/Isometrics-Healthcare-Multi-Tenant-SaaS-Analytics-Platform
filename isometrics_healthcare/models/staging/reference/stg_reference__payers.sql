{{
  config(
    materialized='view',
    tags=['staging', 'reference', 'payer']
  )
}}

with source as (
    select * from {{ source('reference', 'raw_payers') }}
),

renamed as (
    select
        -- Primary Key
        payer_id,

        -- Attributes
        payer_name,
        payer_type,
        reimbursement_rate,
        is_active,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed