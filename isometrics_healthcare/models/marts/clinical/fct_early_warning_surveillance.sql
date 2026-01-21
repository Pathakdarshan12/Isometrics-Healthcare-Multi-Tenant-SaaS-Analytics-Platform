{{
  config(
    materialized='table',
    tags=['marts', 'clinical_quality', 'early_warning', 'patient_safety'],
    cluster_by=['hospital_id', 'metric_date']
  )
}}

/*
  Early Warning & Deterioration Surveillance
  Daily metrics for NEWS scores, vital sign alerts, and rapid response triggers
*/

with vitals as (
    select * from {{ ref('int_clinical__vitals_enriched') }}
),

daily_surveillance as (
    select
        hospital_id,
        date_trunc('day', measurement_datetime) as metric_date,

        -- Volume metrics
        count(distinct vital_id) as total_vital_measurements,
        count(distinct patient_id) as unique_patients_monitored,
        count(distinct encounter_id) as encounters_monitored,

        -- NEWS score distribution
        count(distinct case when news_risk_category = 'High Risk' then vital_id end) as high_risk_measurements,
        count(distinct case when news_risk_category = 'Medium Risk' then vital_id end) as medium_risk_measurements,
        count(distinct case when news_risk_category = 'Low Risk' then vital_id end) as low_risk_measurements,
        count(distinct case when news_risk_category = 'Normal' then vital_id end) as normal_measurements,

        -- Unique patients by risk level
        count(distinct case when news_risk_category = 'High Risk' then patient_id end) as high_risk_patients,
        count(distinct case when news_risk_category = 'Medium Risk' then patient_id end) as medium_risk_patients,

        -- Average NEWS scores
        avg(total_news_score) as avg_news_score,
        max(total_news_score) as max_news_score,
        percentile_cont(0.5) within group (order by total_news_score) as median_news_score,
        percentile_cont(0.95) within group (order by total_news_score) as p95_news_score,

        -- Individual vital abnormalities
        count(distinct case when is_febrile then vital_id end) as febrile_measurements,
        count(distinct case when is_hypothermic then vital_id end) as hypothermic_measurements,
        count(distinct case when is_tachycardic then vital_id end) as tachycardic_measurements,
        count(distinct case when is_bradycardic then vital_id end) as bradycardic_measurements,
        count(distinct case when is_tachypneic then vital_id end) as tachypneic_measurements,
        count(distinct case when is_hypotensive then vital_id end) as hypotensive_measurements,
        count(distinct case when is_hypertensive then vital_id end) as hypertensive_measurements,
        count(distinct case when is_hypoxic then vital_id end) as hypoxic_measurements,

        -- Composite clinical alerts
        count(distinct case when sepsis_alert then vital_id end) as sepsis_alerts,
        count(distinct case when sepsis_alert then patient_id end) as patients_with_sepsis_alert,
        count(distinct case when respiratory_distress_alert then vital_id end) as respiratory_alerts,
        count(distinct case when respiratory_distress_alert then patient_id end) as patients_with_respiratory_alert,
        count(distinct case when hypertensive_crisis_alert then vital_id end) as hypertensive_crisis_alerts,

        -- Rapid deterioration
        count(distinct case when rapid_deterioration_flag then vital_id end) as rapid_deterioration_events,
        count(distinct case when rapid_deterioration_flag then patient_id end) as patients_with_rapid_deterioration,

        -- Pain management
        count(distinct case when has_severe_pain then vital_id end) as severe_pain_measurements,
        avg(case when pain_score is not null then pain_score else null end) as avg_pain_score,

        -- Measurement frequency
        count(distinct vital_id) * 1.0 / count(distinct encounter_id) as avg_measurements_per_encounter,

        current_timestamp() as _dbt_loaded_at

    from vitals
    where measurement_datetime is not null
    group by hospital_id, date_trunc('day', measurement_datetime)
),

with_rates as (
    select
        *,

        -- Risk prevalence rates
        case
            when total_vital_measurements > 0
            then (high_risk_measurements * 100.0) / total_vital_measurements
            else 0
        end as high_risk_rate_pct,

        case
            when total_vital_measurements > 0
            then ((high_risk_measurements + medium_risk_measurements) * 100.0) / total_vital_measurements
            else 0
        end as elevated_risk_rate_pct,

        -- Alert rates
        case
            when total_vital_measurements > 0
            then (sepsis_alerts * 100.0) / total_vital_measurements
            else 0
        end as sepsis_alert_rate_pct,

        case
            when total_vital_measurements > 0
            then (respiratory_alerts * 100.0) / total_vital_measurements
            else 0
        end as respiratory_alert_rate_pct,

        case
            when total_vital_measurements > 0
            then (rapid_deterioration_events * 100.0) / total_vital_measurements
            else 0
        end as rapid_deterioration_rate_pct,

        -- Abnormal vital rates
        case
            when total_vital_measurements > 0
            then (hypotensive_measurements * 100.0) / total_vital_measurements
            else 0
        end as hypotension_rate_pct,

        case
            when total_vital_measurements > 0
            then (hypoxic_measurements * 100.0) / total_vital_measurements
            else 0
        end as hypoxia_rate_pct,

        case
            when total_vital_measurements > 0
            then (tachycardic_measurements * 100.0) / total_vital_measurements
            else 0
        end as tachycardia_rate_pct

    from daily_surveillance
),

with_benchmarks as (
    select
        *,

        -- Alert status (clinical thresholds)
        case
            when high_risk_patients >= 5 then 'High Alert Volume'
            when high_risk_patients >= 2 then 'Moderate Alert Volume'
            else 'Normal Alert Volume'
        end as alert_volume_status,

        case
            when avg_news_score >= 5 then 'High Average Risk'
            when avg_news_score >= 3 then 'Moderate Average Risk'
            else 'Low Average Risk'
        end as population_risk_status,

        case
            when sepsis_alerts >= 3 then 'High Sepsis Alert Day'
            when sepsis_alerts >= 1 then 'Sepsis Alerts Present'
            else 'No Sepsis Alerts'
        end as sepsis_surveillance_status,

        -- Monitoring compliance (expect vitals every 4-8 hours)
        case
            when avg_measurements_per_encounter >= 3 then 'Adequate Monitoring'
            when avg_measurements_per_encounter >= 2 then 'Marginal Monitoring'
            else 'Insufficient Monitoring'
        end as monitoring_frequency_status,

        -- Overall surveillance score (0-100)
        greatest(0, 100 - (high_risk_rate_pct * 5) - (sepsis_alert_rate_pct * 10) - (rapid_deterioration_rate_pct * 8)) as surveillance_quality_score

    from with_rates
)

select * from with_benchmarks