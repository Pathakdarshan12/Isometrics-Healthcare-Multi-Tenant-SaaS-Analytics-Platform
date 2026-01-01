{{
  config(
    materialized='table',
    tags=['marts', 'observability', 'cost'],
    cluster_by=['hospital_id', 'query_date']
  )
}}

/*
  Cost Attribution Model
  Tracks Snowflake compute costs per hospital for chargeback/showback

  Data Source: Snowflake Account Usage
  Granularity: Daily per hospital
  Use Cases:
  - CFO chargeback reports
  - Capacity planning
  - Tenant cost optimization
*/

with query_history as (
    select
        query_id,
        query_text,
        user_name,
        role_name,
        warehouse_name,
        warehouse_size,
        database_name,
        schema_name,
        start_time,
        end_time,
        total_elapsed_time,
        execution_time,
        queued_overload_time,
        bytes_scanned,
        rows_produced,
        credits_used_cloud_services,

        -- Extract hospital_id from query (if present in WHERE clause)
        regexp_substr(query_text, 'hospital_id\\s*=\\s*[\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1) as hospital_id_from_query

    from snowflake.account_usage.query_history
    where
        start_time >= dateadd('day', -90, current_date())
        and database_name = 'ISOMETRICS_DEV'
        and schema_name in ('STAGING', 'INTERMEDIATE', 'MARTS')
),

warehouse_metering as (
    select
        warehouse_name,
        start_time,
        end_time,
        credits_used,
        credits_used_compute,
        credits_used_cloud_services
    from snowflake.account_usage.warehouse_metering_history
    where start_time >= dateadd('day', -90, current_date())
),

-- Aggregate by hospital per day
daily_cost as (
    select
        coalesce(qh.hospital_id_from_query, 'UNATTRIBUTED') as hospital_id,
        date_trunc('day', qh.start_time) as query_date,

        -- Query Metrics
        count(distinct qh.query_id) as query_count,
        sum(qh.total_elapsed_time) / 1000 as total_query_time_seconds,
        avg(qh.execution_time) / 1000 as avg_query_time_seconds,
        max(qh.execution_time) / 1000 as max_query_time_seconds,

        -- Data Volume
        sum(qh.bytes_scanned) / power(1024, 3) as total_gb_scanned,
        sum(qh.rows_produced) as total_rows_produced,

        -- Credits (approximate - distributed based on query time)
        sum(
            -- Proportional credit allocation based on query execution time
            (qh.execution_time * 1.0 / nullif(sum(qh.execution_time) over (partition by date_trunc('day', qh.start_time)), 0))
            * max(wm.credits_used)
        ) as estimated_credits_used,

        -- Cost (assuming $4 per credit - adjust for your pricing)
        estimated_credits_used * 4 as estimated_cost_usd,

        -- Query Types
        count(case when lower(qh.query_text) like '%select%' then 1 end) as select_queries,
        count(case when lower(qh.query_text) like '%insert%' or lower(qh.query_text) like '%update%' then 1 end) as write_queries,
        count(case when lower(qh.query_text) like '%create%' or lower(qh.query_text) like '%alter%' then 1 end) as ddl_queries,

        current_timestamp() as _dbt_loaded_at

    from query_history qh
    left join warehouse_metering wm
        on date_trunc('day', qh.start_time) = date_trunc('day', wm.start_time)
        and qh.warehouse_name = wm.warehouse_name
    group by
        coalesce(qh.hospital_id_from_query, 'UNATTRIBUTED'),
        date_trunc('day', qh.start_time)
),

with_benchmarks as (
    select
        d.*,

        -- Running totals
        sum(estimated_cost_usd) over (
            partition by hospital_id
            order by query_date
            rows between unbounded preceding and current row
        ) as cumulative_cost_usd,

        -- Week-over-week comparison
        lag(estimated_cost_usd, 7) over (
            partition by hospital_id
            order by query_date
        ) as cost_7days_ago,

        case
            when cost_7days_ago > 0
            then ((estimated_cost_usd - cost_7days_ago) * 100.0) / cost_7days_ago
            else 0
        end as cost_change_pct_wow,

        -- Efficiency metrics
        case
            when query_count > 0
            then estimated_cost_usd / query_count
            else 0
        end as cost_per_query,

        case
            when total_gb_scanned > 0
            then estimated_cost_usd / total_gb_scanned
            else 0
        end as cost_per_gb_scanned

    from daily_cost d
)

select * from with_benchmarks