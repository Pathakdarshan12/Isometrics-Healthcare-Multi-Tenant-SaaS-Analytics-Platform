{{
  config(
    materialized='table',
    tags=['marts', 'population_health', 'care_management', 'sdoh'],
    cluster_by=['hospital_id'],
    schema = 'marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  Population Health Dashboard
  Current state snapshot of patient population with risk stratification,
  chronic disease burden, SDOH factors, and care management opportunities
*/

with patient_profiles as (
    select * from {{ ref('int_clinical__patient_profile') }}
),

hospitals as (
    select * from {{ ref('stg_healthcare__hospitals') }}
),

population_summary as (
    select
        pp.hospital_id,

        -- Hospital context
        h.hospital_name,
        h.hospital_type,
        h.region,
        h.contract_tier,

        -- Population size
        count(distinct pp.patient_id) as total_population,

        -- Demographics
        count(distinct case when pp.age_group = 'Pediatric' then pp.patient_id end) as pediatric_patients,
        count(distinct case when pp.age_group = 'Adult' then pp.patient_id end) as adult_patients,
        count(distinct case when pp.age_group = 'Geriatric' then pp.patient_id end) as geriatric_patients,
        avg(pp.age_years) as avg_patient_age,

        -- Clinical complexity
        sum(pp.chronic_condition_count) as total_chronic_conditions,
        avg(pp.chronic_condition_count) as avg_chronic_conditions_per_patient,
        count(distinct case when pp.chronic_condition_count >= 3 then pp.patient_id end) as high_complexity_patients,
        count(distinct case when pp.chronic_condition_count >= 1 then pp.patient_id end) as patients_with_chronic_disease,

        -- Risk stratification
        count(distinct case when pp.clinical_risk_category = 'Very High Risk' then pp.patient_id end) as very_high_risk_patients,
        count(distinct case when pp.clinical_risk_category = 'High Risk' then pp.patient_id end) as high_risk_patients,
        count(distinct case when pp.clinical_risk_category = 'Medium Risk' then pp.patient_id end) as medium_risk_patients,
        count(distinct case when pp.clinical_risk_category = 'Low Risk' then pp.patient_id end) as low_risk_patients,

        -- Utilization patterns
        count(distinct case when pp.utilization_category = 'Frequent ED User' then pp.patient_id end) as frequent_ed_users,
        count(distinct case when pp.utilization_category = 'Frequent Admits' then pp.patient_id end) as frequent_admits,
        count(distinct case when pp.utilization_category = 'High Utilizer' then pp.patient_id end) as high_utilizers,
        sum(pp.ed_visits) as total_ed_visits,
        sum(pp.readmissions) as total_readmissions,

        -- Allergies & safety
        count(distinct case when pp.life_threatening_allergy_count > 0 then pp.patient_id end) as patients_with_life_threatening_allergies,
        count(distinct case when pp.drug_allergy_count > 0 then pp.patient_id end) as patients_with_drug_allergies,
        sum(pp.active_allergy_count) as total_active_allergies,

        -- Insurance coverage
        count(distinct case when pp.active_coverage_count = 0 then pp.patient_id end) as uninsured_patients,
        count(distinct case when pp.primary_plan_type = 'HMO' then pp.patient_id end) as hmo_patients,
        count(distinct case when pp.primary_plan_type = 'PPO' then pp.patient_id end) as ppo_patients,
        avg(pp.primary_deductible_remaining) as avg_deductible_remaining,

        -- Recent clinical status
        count(distinct case when pp.latest_news_score >= 7 then pp.patient_id end) as high_news_score_patients,
        count(distinct case when pp.febrile_rate > 0.5 then pp.patient_id end) as frequently_febrile_patients,
        avg(pp.avg_bmi) as population_avg_bmi,

        -- SDOH factors
        count(distinct case when pp.current_sdoh_risk_category in ('High Risk', 'Medium Risk') then pp.patient_id end) as elevated_sdoh_risk,
        count(distinct case when pp.has_housing_risk then pp.patient_id end) as housing_insecurity,
        count(distinct case when pp.has_food_insecurity then pp.patient_id end) as food_insecurity,
        count(distinct case when pp.has_transportation_barriers then pp.patient_id end) as transportation_barriers,
        avg(pp.current_sdoh_risk_count) as avg_sdoh_risk_factors,

        -- Medication adherence
        avg(pp.patient_engagement_score) as avg_engagement_score,
        count(distinct case when pp.medication_refusals_30days > 0 then pp.patient_id end) as patients_with_med_refusals,
        sum(pp.adverse_reactions_30days) as total_adverse_reactions,

        -- Financial burden
        sum(pp.lifetime_charges) as total_lifetime_charges,
        avg(pp.lifetime_charges) as avg_lifetime_charges_per_patient,

        current_timestamp() as _dbt_loaded_at

    from patient_profiles pp
    inner join hospitals h on pp.hospital_id = h.hospital_id
    group by
        pp.hospital_id,
        h.hospital_name,
        h.hospital_type,
        h.region,
        h.contract_tier
),

with_rates as (
    select
        *,

        -- Prevalence rates
        case
            when total_population > 0
            then (patients_with_chronic_disease * 100.0) / total_population
            else 0
        end as chronic_disease_prevalence_pct,

        case
            when total_population > 0
            then ((very_high_risk_patients + high_risk_patients) * 100.0) / total_population
            else 0
        end as high_risk_prevalence_pct,

        case
            when total_population > 0
            then (frequent_ed_users * 100.0) / total_population
            else 0
        end as frequent_ed_user_rate_pct,

        case
            when total_population > 0
            then (uninsured_patients * 100.0) / total_population
            else 0
        end as uninsured_rate_pct,

        case
            when total_population > 0
            then (elevated_sdoh_risk * 100.0) / total_population
            else 0
        end as sdoh_risk_prevalence_pct,

        case
            when total_population > 0
            then (patients_with_med_refusals * 100.0) / total_population
            else 0
        end as medication_non_adherence_rate_pct,

        -- Utilization rates per 1000 patients
        case
            when total_population > 0
            then (total_ed_visits * 1000.0) / total_population
            else 0
        end as ed_visits_per_1000,

        case
            when total_population > 0
            then (total_readmissions * 1000.0) / total_population
            else 0
        end as readmissions_per_1000

    from population_summary
),

with_care_opportunities as (
    select
        *,

        -- Care management opportunities (ranked by volume)
        very_high_risk_patients + high_risk_patients as care_management_candidates,
        frequent_ed_users + frequent_admits as utilization_management_candidates,
        elevated_sdoh_risk as social_services_candidates,
        patients_with_med_refusals as adherence_support_candidates,

        -- Population health score (0-100, higher is better)
        (
            -- Low chronic disease burden (25 points)
            case
                when chronic_disease_prevalence_pct <= 20 then 25
                when chronic_disease_prevalence_pct <= 30 then 20
                when chronic_disease_prevalence_pct <= 40 then 15
                else 10
            end +
            -- Low high-risk prevalence (25 points)
            case
                when high_risk_prevalence_pct <= 10 then 25
                when high_risk_prevalence_pct <= 20 then 20
                when high_risk_prevalence_pct <= 30 then 15
                else 10
            end +
            -- Low ED utilization (20 points)
            case
                when ed_visits_per_1000 <= 100 then 20
                when ed_visits_per_1000 <= 200 then 15
                when ed_visits_per_1000 <= 300 then 10
                else 5
            end +
            -- Good medication adherence (15 points)
            case
                when medication_non_adherence_rate_pct <= 5 then 15
                when medication_non_adherence_rate_pct <= 10 then 10
                else 5
            end +
            -- Low SDOH risk (15 points)
            case
                when sdoh_risk_prevalence_pct <= 10 then 15
                when sdoh_risk_prevalence_pct <= 20 then 10
                else 5
            end
        ) as population_health_score,

        -- Priority ranking for intervention
        case
            when very_high_risk_patients > 10 or frequent_ed_users > 5 then 'Critical Priority'
            when high_risk_patients > 20 or elevated_sdoh_risk > 10 then 'High Priority'
            when medium_risk_patients > 50 then 'Medium Priority'
            else 'Monitoring'
        end as intervention_priority

    from with_rates
)

select * from with_care_opportunities