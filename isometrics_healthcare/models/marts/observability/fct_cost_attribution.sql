{{ config(
    materialized='table',
    tags=['marts', 'observability', 'cost'],
    cluster_by=['hospital_id', 'metric_date'],
    schema='marts',
    post_hook=["{{ apply_rls_policy() }}"]
) }}

/*
    Cost Attribution Model - ACTUAL COSTS
    Tracks real costs per hospital from Snowflake query history and warehouse metering
*/

with warehouse_costs as (
    select
        start_time,
        warehouse_name,
        credits_used,
        credits_used * 4 as cost_usd  -- Adjust multiplier based on your Snowflake contract
    from snowflake.account_usage.warehouse_metering_history
    where start_time >= dateadd('day', -90, current_date())
),

query_attribution as (
    select
        qh.query_id,
        qh.start_time,
        qh.warehouse_name,
        qh.execution_status,
        qh.total_elapsed_time / 1000.0 as execution_time_seconds,
        qh.credits_used_cloud_services,

        -- Extract hospital_id from query patterns
        coalesce(
            regexp_substr(qh.query_text, 'hospital_id\\s*=\\s*[\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1),
            regexp_substr(qh.query_text, 'hospital_id\\s*IN\\s*\\([\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1),
            'UNATTRIBUTED'
        ) as hospital_id,

        qh.query_text

    from snowflake.account_usage.query_history qh
    where qh.start_time >= dateadd('day', -90, current_date())
      and qh.database_name = current_database()
      and qh.execution_status = 'SUCCESS'
),

query_costs as (
    select
        qa.hospital_id,
        date_trunc('day', qa.start_time) as metric_date,

        -- Query metrics
        count(distinct qa.query_id) as queries_executed,
        sum(qa.execution_time_seconds) as total_execution_time_seconds,

        -- Cloud services costs (directly attributable)
        sum(qa.credits_used_cloud_services) as cloud_services_credits,
        sum(qa.credits_used_cloud_services) * 4 as cloud_services_cost_usd,

        -- Warehouse costs (proportional allocation)
        sum(qa.execution_time_seconds) as query_execution_time,

        current_timestamp() as _dbt_loaded_at

    from query_attribution qa
    group by qa.hospital_id, date_trunc('day', qa.start_time)
),

warehouse_allocation as (
    select
        qc.hospital_id,
        qc.metric_date,
        qc.queries_executed,
        qc.total_execution_time_seconds,
        qc.cloud_services_credits,
        qc.cloud_services_cost_usd,

        -- Total warehouse time for the day
        sum(qc.query_execution_time) over (partition by qc.metric_date) as total_warehouse_time_day,

        -- Proportional share of warehouse costs
        case
            when total_warehouse_time_day > 0
            then (qc.query_execution_time / total_warehouse_time_day) * wc.cost_usd
            else 0
        end as allocated_warehouse_cost_usd,

        qc._dbt_loaded_at

    from query_costs qc
    left join warehouse_costs wc
        on date_trunc('day', wc.start_time) = qc.metric_date
),

daily_costs as (
    select
        hospital_id,
        metric_date,
        queries_executed,
        total_execution_time_seconds,

        -- Total costs
        cloud_services_cost_usd,
        sum(allocated_warehouse_cost_usd) as warehouse_cost_usd,
        cloud_services_cost_usd + sum(allocated_warehouse_cost_usd) as total_cost_usd,

        cloud_services_credits,
        cloud_services_credits + (sum(allocated_warehouse_cost_usd) / 4) as total_credits_used,

        'ACTUAL' as calculation_method,
        'Based on snowflake.account_usage query history and warehouse metering' as note,

        _dbt_loaded_at

    from warehouse_allocation
    group by
        hospital_id,
        metric_date,
        queries_executed,
        total_execution_time_seconds,
        cloud_services_cost_usd,
        cloud_services_credits,
        _dbt_loaded_at
),

with_cumulative as (
    select
        hospital_id,
        metric_date,
        queries_executed,
        total_execution_time_seconds,
        cloud_services_cost_usd,
        warehouse_cost_usd,
        total_cost_usd,
        total_credits_used,

        -- Running total
        sum(total_cost_usd) over (
            partition by hospital_id
            order by metric_date
            rows between unbounded preceding and current row
        ) as cumulative_cost_usd,

        -- Week over week
        lag(total_cost_usd, 7) over (
            partition by hospital_id
            order by metric_date
        ) as cost_7days_ago,

        case
            when cost_7days_ago > 0
            then ((total_cost_usd - cost_7days_ago) * 100.0) / cost_7days_ago
            else 0
        end as cost_change_pct_wow,

        calculation_method,
        note,
        _dbt_loaded_at

    from daily_costs
)

select * from with_cumulative