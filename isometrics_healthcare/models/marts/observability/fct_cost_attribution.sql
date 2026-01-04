{{
  config(
    materialized='table',
    tags=['marts', 'observability', 'cost'],
    cluster_by=['hospital_id', 'metric_date'],
    schema = 'marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  Cost Attribution Model - SIMPLIFIED VERSION
  Tracks estimated costs per hospital based on query patterns

  NOTE: This is a simplified version for demo purposes.
  In production, you would use Snowflake's ACCOUNT_USAGE views
  which require ACCOUNTADMIN privileges.

  To enable full cost tracking:
  1. Grant IMPORTED PRIVILEGES on SNOWFLAKE database to your role
  2. Use snowflake.account_usage.query_history
  3. Use snowflake.account_usage.warehouse_metering_history
  with query_history as (
    select
        query_id,
        query_text,
        start_time,
        execution_time,
        credits_used_cloud_services,
        regexp_substr(query_text, 'hospital_id\\s*=\\s*[\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1) as hospital_id
    from snowflake.account_usage.query_history
    where start_time >= dateadd('day', -90, current_date())
      and database_name = current_database()
),
*/
with daily_metrics as (
    -- Estimate costs based on encounter volume as a proxy
    -- In production, replace this with actual query history
    select
        hospital_id,
        admission_date_day as metric_date,

        -- Volume-based cost estimation (demo purposes only)
        count(*) as encounters_processed,
        count(*) * 0.001 as estimated_credits_used,  -- $0.001 per encounter estimate
        estimated_credits_used * 4 as estimated_cost_usd,  -- $4 per credit

        -- Metadata
        'ESTIMATED' as calculation_method,
        'Based on encounter volume - not actual query costs' as note,

        current_timestamp() as _dbt_loaded_at

    from ISOMETRICS_DEV.dbt_dev_marts.fct_encounters
    where admission_date_day >= dateadd('day', -90, current_date())
    group by hospital_id, admission_date_day
),

with_cumulative as (
    select
        hospital_id,
        metric_date,
        encounters_processed,
        estimated_credits_used,
        estimated_cost_usd,

        -- Running total
        sum(estimated_cost_usd) over (
            partition by hospital_id
            order by metric_date
            rows between unbounded preceding and current row
        ) as cumulative_cost_usd,

        -- Week over week
        lag(estimated_cost_usd, 7) over (
            partition by hospital_id
            order by metric_date
        ) as cost_7days_ago,

        case
            when cost_7days_ago > 0
            then ((estimated_cost_usd - cost_7days_ago) * 100.0) / cost_7days_ago
            else 0
        end as cost_change_pct_wow,

        calculation_method,
        note,
        _dbt_loaded_at

    from daily_metrics
)

select * from with_cumulative