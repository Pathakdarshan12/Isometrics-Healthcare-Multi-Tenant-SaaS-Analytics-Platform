{{
  config(
    materialized='incremental',
    unique_key='transaction_id',
    incremental_strategy='merge',
    cluster_by=['hospital_id', 'transaction_date'],
    on_schema_change='fail',
    tags=['marts', 'incremental', 'financial']
  )
}}

/*
  Incremental Strategy: MERGE
  Why merge here instead of delete+insert?
  - Billing status can change (Pending -> Paid)
  - Need to UPDATE existing records, not just INSERT new ones
  - Merge handles both INSERT and UPDATE in single operation
*/

with revenue_cycle as (
    select * from {{ ref('int_financial__revenue_cycle') }}
),

final as (
    select
        -- Keys
        transaction_id,
        hospital_id,
        encounter_id,
        patient_id,
        payer_id,

        -- Payer Info
        payer_name,
        payer_type,
        expected_reimbursement_rate,

        -- Encounter Context
        encounter_type,
        discharge_date,

        -- Transaction Details
        transaction_date,
        days_in_ar,

        -- Financial Amounts
        charge_amount,
        payment_amount,
        adjustment_amount,
        collected_amount,
        denied_amount,

        -- Calculations
        collection_rate_pct,
        expected_payment,
        payment_variance,

        -- Status
        payment_status,
        denial_reason,
        is_denied,
        is_paid,
        is_pending,

        -- AR Flags
        is_over_30_days,
        is_over_60_days,
        is_over_90_days,
        ar_aging_bucket,

        -- Metadata
        current_timestamp() as _dbt_updated_at

    from revenue_cycle

    {% if is_incremental() %}
        -- Process transactions from last 7 days (to catch status updates)
        where transaction_date >= dateadd('day', -7, current_date())
    {% endif %}
)

select * from final