{{
  config(
    materialized='table',
    tags=['marts', 'clinical_quality', 'cms_measures', 'regulatory'],
    cluster_by=['hospital_id', 'reporting_quarter'],
    schema='marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  CMS core-measure performance from abstracted measure records (raw_quality_measures).
  Complements fct_cms_core_measures_performance_dashboard, which infers measures
  from vitals/orders; this model reports what chart abstraction recorded.

  Grain: hospital_id x measure_code x reporting_quarter
  Performance rate = numerator met / (denominator - exclusions), per CMS convention.
*/

with results as (
    select * from {{ ref('int_quality__measure_results') }}
),

comorbidity as (
    select hospital_id, patient_id, charlson_index
    from {{ ref('int_clinical__comorbidity_index') }}
),

aggregated as (
    select
        r.hospital_id,
        r.measure_code,
        any_value(r.measure_name) as measure_name,
        any_value(r.measure_category) as measure_category,
        r.reporting_year,
        r.reporting_quarter,

        count(*) as total_cases,
        count_if(r.denominator_eligible) as denominator_cases,
        count_if(r.exclusion_applied) as excluded_cases,
        count_if(r.is_measure_eligible) as eligible_cases,
        count_if(r.is_performance_met) as numerator_cases,
        count_if(r.is_measure_eligible and not r.is_performance_met) as care_gap_cases,

        {{ calculate_percentage('count_if(r.is_performance_met)', 'count_if(r.is_measure_eligible)') }}
            as performance_rate_pct,

        -- Timeliness (timed measures only)
        median(r.time_to_treatment_minutes) as median_time_to_treatment_minutes,
        percentile_cont(0.90) within group (order by r.time_to_treatment_minutes)
            as p90_time_to_treatment_minutes,
        any_value(r.target_minutes) as target_minutes,
        {{ calculate_percentage('count_if(r.met_time_target)', 'count_if(r.met_time_target is not null)') }}
            as met_time_target_pct,

        -- Outcome and case-mix context
        {{ calculate_percentage('count_if(r.is_mortality)', 'count(*)') }} as cohort_mortality_rate_pct,
        round(avg(c.charlson_index), 2) as avg_charlson_index

    from results r
    left join comorbidity c
        on r.patient_id = c.patient_id
        and r.hospital_id = c.hospital_id
    group by r.hospital_id, r.measure_code, r.reporting_year, r.reporting_quarter
)

select
    {{ tenant_surrogate_key(['measure_code', 'reporting_quarter']) }} as quality_measure_performance_key,
    *,
    case
        when performance_rate_pct is null then 'No eligible cases'
        when performance_rate_pct >= 90 then 'Meets target'
        when performance_rate_pct >= 75 then 'Needs improvement'
        else 'Below target'
    end as performance_status,
    current_timestamp() as _dbt_updated_at
from aggregated
