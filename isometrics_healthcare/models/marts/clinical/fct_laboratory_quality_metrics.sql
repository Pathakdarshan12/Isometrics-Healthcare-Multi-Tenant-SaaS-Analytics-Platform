{{
  config(
    materialized='table',
    tags=['marts', 'clinical_quality', 'laboratory', 'turnaround_time'],
    cluster_by=['hospital_id', 'metric_date']
  )
}}

/*
  Laboratory Quality Metrics
  Tracks turnaround times, critical values, test volumes, and quality indicators
*/

with lab_results as (
    select * from {{ ref('int_clinical__lab_results_enriched') }}
),

daily_metrics as (
    select
        hospital_id,
        date_trunc('day', result_datetime) as metric_date,

        -- Volume metrics
        count(distinct result_id) as total_lab_results,
        count(distinct patient_id) as unique_patients_tested,
        count(distinct encounter_id) as encounters_with_labs,
        count(distinct test_code) as unique_tests_performed,

        -- By panel category
        count(distinct case when lab_panel_category = 'Complete Blood Count' then result_id end) as cbc_count,
        count(distinct case when lab_panel_category = 'Basic Metabolic Panel' then result_id end) as bmp_count,
        count(distinct case when lab_panel_category = 'Comprehensive Metabolic Panel' then result_id end) as cmp_count,
        count(distinct case when lab_panel_category = 'Liver Function Panel' then result_id end) as lft_count,
        count(distinct case when lab_panel_category = 'Lipid Panel' then result_id end) as lipid_count,
        count(distinct case when lab_panel_category = 'Cardiac Marker' then result_id end) as cardiac_marker_count,
        count(distinct case when lab_panel_category = 'Coagulation Panel' then result_id end) as coag_count,

        -- Result status
        count(distinct case when is_final then result_id end) as final_results,
        count(distinct case when is_preliminary then result_id end) as preliminary_results,

        -- Abnormal results
        count(distinct case when is_abnormal then result_id end) as abnormal_results,
        count(distinct case when is_high then result_id end) as high_results,
        count(distinct case when is_low then result_id end) as low_results,

        -- Critical values
        count(distinct case when is_critical_value then result_id end) as critical_values,
        count(distinct case when is_critical_value then patient_id end) as patients_with_critical_values,

        -- Turnaround time metrics
        avg(turnaround_time_hours) as avg_turnaround_hours,
        percentile_cont(0.5) within group (order by turnaround_time_hours) as median_turnaround_hours,
        percentile_cont(0.95) within group (order by turnaround_time_hours) as p95_turnaround_hours,
        max(turnaround_time_hours) as max_turnaround_hours,

        -- Turnaround by urgency (STAT labs)
        avg(case when order_completion_hours <= 1 then turnaround_time_hours end) as avg_stat_turnaround_hours,
        percentile_cont(0.5) within group (order by case when order_completion_hours <= 1 then turnaround_time_hours end) as median_stat_turnaround_hours,

        -- Results within target timeframes
        count(distinct case when turnaround_time_hours <= 2 then result_id end) as results_within_2hrs,
        count(distinct case when turnaround_time_hours <= 4 then result_id end) as results_within_4hrs,
        count(distinct case when turnaround_time_hours <= 24 then result_id end) as results_within_24hrs,

        -- Trending analysis
        count(distinct case when result_sequence > 1 then result_id end) as repeat_tests,
        count(distinct case when trend_direction = 'Increasing' then result_id end) as increasing_trends,
        count(distinct case when trend_direction = 'Decreasing' then result_id end) as decreasing_trends,

        -- Out of range severity
        avg(case when is_abnormal then out_of_range_value else null end) as avg_out_of_range_value,
        max(case when is_abnormal then out_of_range_value else null end) as max_out_of_range_value,

        current_timestamp() as _dbt_loaded_at

    from lab_results
    where result_datetime is not null
    group by hospital_id, date_trunc('day', result_datetime)
),

with_rates as (
    select
        *,

        -- Abnormal rates
        case
            when total_lab_results > 0
            then (abnormal_results * 100.0) / total_lab_results
            else 0
        end as abnormal_rate_pct,

        case
            when total_lab_results > 0
            then (critical_values * 100.0) / total_lab_results
            else 0
        end as critical_value_rate_pct,

        -- Turnaround compliance rates
        case
            when total_lab_results > 0
            then (results_within_2hrs * 100.0) / total_lab_results
            else 0
        end as within_2hr_rate_pct,

        case
            when total_lab_results > 0
            then (results_within_4hrs * 100.0) / total_lab_results
            else 0
        end as within_4hr_rate_pct,

        case
            when total_lab_results > 0
            then (results_within_24hrs * 100.0) / total_lab_results
            else 0
        end as within_24hr_rate_pct,

        -- Panel distribution percentages
        case
            when total_lab_results > 0
            then (cbc_count * 100.0) / total_lab_results
            else 0
        end as cbc_pct,

        case
            when total_lab_results > 0
            then (cardiac_marker_count * 100.0) / total_lab_results
            else 0
        end as cardiac_marker_pct,

        -- Repeat test rate (efficiency indicator)
        case
            when total_lab_results > 0
            then (repeat_tests * 100.0) / total_lab_results
            else 0
        end as repeat_test_rate_pct

    from daily_metrics
),

with_quality_indicators as (
    select
        *,

        -- Turnaround time compliance status
        case
            when median_turnaround_hours <= 4 then 'Excellent'
            when median_turnaround_hours <= 8 then 'Good'
            when median_turnaround_hours <= 12 then 'Fair'
            else 'Needs Improvement'
        end as turnaround_performance,

        -- STAT lab performance
        case
            when median_stat_turnaround_hours <= 1 then 'Meets STAT Target'
            when median_stat_turnaround_hours <= 2 then 'Marginal STAT Performance'
            else 'Below STAT Target'
        end as stat_performance_status,

        -- Critical value response readiness
        case
            when critical_values >= 5 then 'High Critical Volume'
            when critical_values >= 2 then 'Moderate Critical Volume'
            when critical_values >= 1 then 'Low Critical Volume'
            else 'No Critical Values'
        end as critical_value_status,

        -- Lab quality score (0-100)
        (
            -- Turnaround time component (40 points)
            case
                when within_4hr_rate_pct >= 90 then 40
                when within_4hr_rate_pct >= 75 then 30
                when within_4hr_rate_pct >= 50 then 20
                else within_4hr_rate_pct * 0.4
            end +
            -- STAT performance component (30 points)
            case
                when median_stat_turnaround_hours <= 1 then 30
                when median_stat_turnaround_hours <= 2 then 20
                else 10
            end +
            -- Result finalization rate (20 points)
            case
                when (final_results * 100.0 / nullif(total_lab_results, 0)) >= 95 then 20
                when (final_results * 100.0 / nullif(total_lab_results, 0)) >= 85 then 15
                else 10
            end +
            -- Efficiency (10 points - lower repeat rate is better)
            case
                when repeat_test_rate_pct <= 10 then 10
                when repeat_test_rate_pct <= 20 then 7
                else 5
            end
        ) as lab_quality_score

    from with_rates
)

select * from with_quality_indicators