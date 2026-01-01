{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'financial']
  )
}}

with encounters as (
    select * from {{ ref('stg_healthcare__encounters') }}
),

billing as (
    select * from {{ ref('stg_healthcare__billing_transactions') }}
),

payers as (
    select * from {{ ref('stg_reference__payers') }}
),

revenue_detail as (
    select
        -- Identifiers
        b.transaction_id,
        b.hospital_id,
        b.encounter_id,
        b.patient_id,
        b.payer_id,

        -- Payer info
        p.payer_name,
        p.payer_type,
        p.reimbursement_rate as expected_reimbursement_rate,

        -- Encounter info
        e.encounter_type,
        e.discharge_date,

        -- Transaction dates
        b.transaction_date,

        -- Calculate days in AR (accounts receivable)
        datediff('day', e.discharge_date, b.transaction_date) as days_in_ar,

        -- Financial amounts
        b.charge_amount,
        b.payment_amount,
        b.adjustment_amount,
        b.collected_amount,
        b.denied_amount,

        -- Rates
        b.collection_rate_pct,

        -- Expected vs actual payment variance
        (b.charge_amount * p.reimbursement_rate) as expected_payment,
        b.payment_amount - (b.charge_amount * p.reimbursement_rate) as payment_variance,

        -- Status
        b.payment_status,
        b.denial_reason,
        b.is_denied,
        b.is_paid,
        b.is_pending,

        -- Flags
        case when days_in_ar > 90 then true else false end as is_over_90_days,
        case when days_in_ar > 60 then true else false end as is_over_60_days,
        case when days_in_ar > 30 then true else false end as is_over_30_days,

        -- AR aging buckets
        case
            when days_in_ar <= 30 then '0-30 days'
            when days_in_ar <= 60 then '31-60 days'
            when days_in_ar <= 90 then '61-90 days'
            when days_in_ar <= 120 then '91-120 days'
            else '120+ days'
        end as ar_aging_bucket

    from billing b
    inner join payers p on b.payer_id = p.payer_id
    inner join encounters e on b.encounter_id = e.encounter_id
)

select * from revenue_detail