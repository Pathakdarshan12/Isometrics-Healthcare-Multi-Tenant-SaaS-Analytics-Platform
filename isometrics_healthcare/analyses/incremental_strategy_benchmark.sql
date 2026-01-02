{{ config(
    materialized='view',
    schema='analysis',
    tags=['analysis', 'performance']
) }}

/*
  Incremental Strategy Performance Benchmark
  Compares execution time and cost between:
  1. Full Refresh
  2. Incremental with MERGE
  3. Incremental with DELETE+INSERT
*/

-- Query 1: Full Refresh Performance
with full_refresh_stats as (
    select
        'full_refresh' as strategy,
        query_id,
        start_time,
        total_elapsed_time / 1000 as execution_seconds,
        bytes_scanned / power(1024, 3) as gb_scanned,
        rows_produced,
        credits_used_cloud_services * 4 as estimated_cost_usd
    from snowflake.account_usage.query_history
    where
        query_text ilike '%create or replace table%fct_encounters%'
        and execution_status = 'SUCCESS'
        and start_time >= dateadd('day', -30, current_date())
    order by start_time desc
    limit 10
),

-- Query 2: Incremental MERGE Performance
incremental_merge_stats as (
    select
        'incremental_merge' as strategy,
        query_id,
        start_time,
        total_elapsed_time / 1000 as execution_seconds,
        bytes_scanned / power(1024, 3) as gb_scanned,
        rows_produced,
        credits_used_cloud_services * 4 as estimated_cost_usd
    from snowflake.account_usage.query_history
    where
        query_text ilike '%merge into%fct_encounters%'
        and execution_status = 'SUCCESS'
        and start_time >= dateadd('day', -30, current_date())
    order by start_time desc
    limit 10
),

-- Query 3: Incremental DELETE+INSERT Performance
incremental_delete_insert_stats as (
    select
        'incremental_delete_insert' as strategy,
        query_id,
        start_time,
        total_elapsed_time / 1000 as execution_seconds,
        bytes_scanned / power(1024, 3) as gb_scanned,
        rows_produced,
        credits_used_cloud_services * 4 as estimated_cost_usd
    from snowflake.account_usage.query_history
    where
        query_text ilike '%delete from%fct_encounters%'
        and execution_status = 'SUCCESS'
        and start_time >= dateadd('day', -30, current_date())
    order by start_time desc
    limit 10
),

-- Combine all strategies
all_strategies as (
    select * from full_refresh_stats
    union all
    select * from incremental_merge_stats
    union all
    select * from incremental_delete_insert_stats
),

-- Calculate summary statistics
benchmark_summary as (
    select
        strategy,
        count(*) as run_count,
        avg(execution_seconds) as avg_execution_seconds,
        min(execution_seconds) as min_execution_seconds,
        max(execution_seconds) as max_execution_seconds,
        percentile_cont(0.5) within group (order by execution_seconds) as median_execution_seconds,
        avg(gb_scanned) as avg_gb_scanned,
        avg(estimated_cost_usd) as avg_cost_usd,
        sum(estimated_cost_usd) as total_cost_usd
    from all_strategies
    group by strategy
)

select
    strategy,
    run_count,
    round(avg_execution_seconds, 2) as avg_seconds,
    round(median_execution_seconds, 2) as median_seconds,
    round(avg_gb_scanned, 2) as avg_gb_scanned,
    round(avg_cost_usd, 2) as avg_cost_usd,

    -- Calculate improvement vs full refresh
    round(
        100.0 * (1 - (avg_execution_seconds / max(avg_execution_seconds) over ())),
        1
    ) as time_improvement_pct,

    round(
        100.0 * (1 - (avg_cost_usd / max(avg_cost_usd) over ())),
        1
    ) as cost_improvement_pct

from benchmark_summary
order by avg_execution_seconds;