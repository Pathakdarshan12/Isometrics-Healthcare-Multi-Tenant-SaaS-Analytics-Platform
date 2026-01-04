{{ config(
    materialized='table',
    tags=['marts', 'clinical', 'provider_performance'],
    cluster_by=['hospital_id', 'provider_id'],
    schema = 'marts',
    post_hook=["{{ apply_rls_policy() }}"]
) }}

with patient_journey as (
    select * from {{ ref('int_patient__journey') }}
    WHERE CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DBT_DEV_ROLE') -- Admin/Dev roles see everything
),

base_metrics as (
    select
        hospital_id,
        provider_id,
        provider_full_name,
        specialty,
        department,
        provider_type,

        min(admission_date) as first_encounter_date,
        max(admission_date) as last_encounter_date,
        datediff(
            'day',
            min(admission_date),
            max(admission_date)
        ) as days_active,

        count(distinct encounter_id) as total_encounters,
        count(distinct patient_id) as unique_patients,
        count(distinct case when encounter_type = 'Inpatient' then encounter_id end) as inpatient_encounters,
        count(distinct case when encounter_type = 'Emergency' then encounter_id end) as emergency_encounters,

        sum(case when is_30day_return then 1 else 0 end) as readmissions_30day,
        sum(case when is_mortality then 1 else 0 end) as mortality_count,

        avg(length_of_stay) as avg_length_of_stay,
        percentile_cont(0.5) within group (order by length_of_stay) as median_length_of_stay,

        sum(total_charges) as total_charges,
        avg(total_charges) as avg_charge_per_encounter,

        count(case when severity_level = 'Critical' then 1 end) as critical_cases,
        count(case when severity_level = 'High' then 1 end) as high_severity_cases,

        count(distinct case when patient_risk_category = 'High Risk' then patient_id end) as high_risk_patients,

        current_timestamp() as _dbt_loaded_at

    from patient_journey
    group by
        hospital_id,
        provider_id,
        provider_full_name,
        specialty,
        department,
        provider_type
),

provider_metrics as (
    select
        *,

        case
            when inpatient_encounters > 0
            then (readmissions_30day * 100.0) / inpatient_encounters
            else 0
        end as readmission_rate_pct,

        case
            when total_encounters > 0
            then (mortality_count * 100.0) / total_encounters
            else 0
        end as mortality_rate_pct,

        case
            when total_encounters > 0
            then ((critical_cases + high_severity_cases) * 100.0) / total_encounters
            else 0
        end as complex_case_rate_pct,

        case
            when days_active > 0
            then total_encounters * 1.0 / days_active
            else 0
        end as encounters_per_day

    from base_metrics
),

with_benchmarks as (
    select
        p.*,

        percent_rank() over (
            partition by hospital_id, specialty
            order by readmission_rate_pct
        ) as readmission_rate_percentile,

        percent_rank() over (
            partition by hospital_id, specialty
            order by avg_length_of_stay
        ) as los_percentile,

        percent_rank() over (
            partition by hospital_id, specialty
            order by total_encounters desc
        ) as volume_percentile,

        case
            when readmission_rate_pct < 5 then 'Excellent'
            when readmission_rate_pct < 10 then 'Good'
            when readmission_rate_pct < 15 then 'Needs Improvement'
            else 'Critical'
        end as readmission_performance,

        case
            when encounters_per_day >= 15 then 'High Volume'
            when encounters_per_day >= 10 then 'Medium Volume'
            else 'Low Volume'
        end as productivity_category

    from provider_metrics p
)

select * from with_benchmarks