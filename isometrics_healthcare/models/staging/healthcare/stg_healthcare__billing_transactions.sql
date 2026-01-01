{{
  config(
    materialized='view',
    tags=['staging', 'bronze', 'billing']
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_billing_transactions') }}
),

renamed as (
    select
        -- Primary Key
        transaction_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        encounter_id,
        patient_id,
        payer_id,

        -- Transaction Details
        transaction_date,
        charge_amount,
        payment_amount,
        adjustment_amount,
        denial_reason,
        payment_status,

        -- Calculated Fields
        case
            when payment_status = 'Paid' then payment_amount
            else 0
        end as collected_amount,

        case
            when payment_status = 'Denied' then charge_amount
            else 0
        end as denied_amount,

        case
            when payment_status in ('Paid', 'Partial')
            then payment_amount * 100.0 / nullif(charge_amount, 0)
            else 0
        end as collection_rate_pct,

        -- Flags
        case when payment_status = 'Denied' then true else false end as is_denied,
        case when payment_status = 'Paid' then true else false end as is_paid,
        case when payment_status = 'Pending' then true else false end as is_pending,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed