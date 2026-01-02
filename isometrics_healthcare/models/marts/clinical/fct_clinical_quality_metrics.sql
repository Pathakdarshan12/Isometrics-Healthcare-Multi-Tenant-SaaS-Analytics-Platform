{{ config(
    materialized='table',
    tags=['marts', 'clinical', 'quality'],
    cluster_by=['hospital_id', 'metric_date']
) }}

with patient_journey as (
    select * from {{ ref('int_patient__journey') }}
),

base_metrics as (
    select
        hospital_id,
        admission_date_day as metric_date,

        -- Volume Metrics
        count(distinct encounter_id) as total_encounters,
        count(distinct case when encounter_type = 'Inpatient' then encounter_id end) as inpatient_encounters,
        count(distinct case when encounter_type = 'Emergency' then encounter_id end) as emergency_encounters,
        count(distinct patient_id) as unique_patients,

        -- Readmissions
        sum(case when is_30day_return then 1 else 0 end) as readmissions_30day,
        sum(case when is_30day_return and not is_30day_return then 1 else 0 end) as returns_30day_non_readmit,
        count(distinct case when encounter_type = 'Inpatient' then encounter_id end) as inpatient_denominator,

        -- Mortality
        sum(case when is_mortality then 1 else 0 end) as mortality_count,

        -- LOS
        avg(length_of_stay) as avg_length_of_stay,
        percentile_cont(0.5) within group (order by length_of_stay) as median_length_of_stay,
        max(length_of_stay) as max_length_of_stay,

        -- Risk
        count(distinct case when patient_risk_category = 'High Risk' then patient_id end) as high_risk_patients,
        count(distinct case when patient_risk_category = 'Medium Risk' then patient_id end) as medium_risk_patients,
        count(distinct case when patient_risk_category = 'Low Risk' then patient_id end) as low_risk_patients,

        -- Financial
        sum(case when is_30day_return then total_charges else 0 end) as readmission_charges,

        -- ED
        count(distinct case when is_emergency and is_7day_return then encounter_id end) as ed_7day_returns,

        current_timestamp() as _dbt_loaded_at

    from patient_journey
    group by hospital_id, admission_date_day
)

select
    *,
    case
        when inpatient_denominator > 0
        then (readmissions_30day * 100.0) / inpatient_denominator
        else 0
    end as readmission_rate_30day_pct,

    case
        when total_encounters > 0
        then (mortality_count * 100.0) / total_encounters
        else 0
    end as mortality_rate_pct
from base_metrics