{{
  config(
    materialized='table',
    tags=['marts', 'financial', 'revenue'],
    cluster_by=['hospital_id', 'metric_date'],
    schema = 'marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  Financial Performance Metrics
  Daily revenue cycle KPIs per hospital
*/

with revenue_cycle as (
    select * from {{ ref('int_financial__revenue_cycle') }}
    WHERE CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DBT_DEV_ROLE') -- Admin/Dev roles see everything
),

daily_financial_metrics as (
    select
        hospital_id,
        date_trunc('day', transaction_date) as metric_date,

        -- Volume Metrics
        count(distinct transaction_id) as total_transactions,
        count(distinct encounter_id) as encounters_billed,

        -- Revenue Metrics
        sum(charge_amount) as total_charges,
        sum(payment_amount) as total_payments,
        sum(adjustment_amount) as total_adjustments,
        sum(collected_amount) as total_collections,
        sum(denied_amount) as total_denials,

        -- Averages
        avg(charge_amount) as avg_charge_per_transaction,
        avg(payment_amount) as avg_payment_per_transaction,

        -- Collection Performance
        case
            when sum(charge_amount) > 0
            then (sum(collected_amount) * 100.0) / sum(charge_amount)
            else 0
        end as net_collection_rate_pct,

        -- Denial Rate
        count(case when is_denied then 1 end) as denial_count,
        case
            when count(*) > 0
            then (count(case when is_denied then 1 end) * 100.0) / count(*)
            else 0
        end as denial_rate_pct,

        -- Days in AR Metrics
        avg(days_in_ar) as avg_days_in_ar,
        percentile_cont(0.5) within group (order by days_in_ar) as median_days_in_ar,

        -- AR Aging
        sum(case when is_over_30_days then charge_amount else 0 end) as ar_over_30_days,
        sum(case when is_over_60_days then charge_amount else 0 end) as ar_over_60_days,
        sum(case when is_over_90_days then charge_amount else 0 end) as ar_over_90_days,

        -- Payer Mix
        count(distinct case when payer_type = 'Government' then transaction_id end) as government_payer_count,
        count(distinct case when payer_type = 'Commercial' then transaction_id end) as commercial_payer_count,
        count(distinct case when payer_type = 'Self-Pay' then transaction_id end) as self_pay_count,

        -- Payment Status
        count(case when is_paid then 1 end) as paid_count,
        count(case when is_pending then 1 end) as pending_count,

        -- Expected vs Actual Variance
        sum(payment_variance) as total_payment_variance,
        avg(payment_variance) as avg_payment_variance,

        current_timestamp() as _dbt_loaded_at

    from revenue_cycle
    group by hospital_id, date_trunc('day', transaction_date)
)

select * from daily_financial_metrics