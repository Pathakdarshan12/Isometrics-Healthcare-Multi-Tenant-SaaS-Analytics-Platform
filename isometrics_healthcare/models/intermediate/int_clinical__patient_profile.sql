{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'clinical', 'medications', 'safety']
  )
}}

with patients as (
    select * from {{ ref('stg_healthcare__patients') }}
),

hospitals as (
    select * from {{ ref('stg_healthcare__hospitals') }}
),

-- Active problems
active_problems as (
    select
        patient_id,
        hospital_id,
        count(distinct problem_id) as active_problem_count,
        count(distinct case when is_chronic then problem_id end) as chronic_condition_count,
        listagg(diagnosis_description, '; ') within group (order by onset_date desc) as active_diagnoses_list
    from {{ ref('stg_healthcare__problem_list') }}
    where is_active = true
    group by patient_id, hospital_id
),

-- Active allergies
active_allergies as (
    select
        patient_id,
        hospital_id,
        count(distinct allergy_id) as active_allergy_count,
        count(distinct case when is_life_threatening then allergy_id end) as life_threatening_allergy_count,
        count(distinct case when is_drug_allergy then allergy_id end) as drug_allergy_count,
        listagg(allergen_name, '; ') within group (order by documentation_date desc) as active_allergies_list
    from {{ ref('stg_healthcare__patient_allergies') }}
    where is_active = true
    group by patient_id, hospital_id
),

-- Insurance coverage
current_coverage as (
    select
        patient_id,
        hospital_id,
        count(distinct coverage_id) as active_coverage_count,
        max(case when is_primary then payer_id end) as primary_payer_id,
        max(case when is_primary then plan_type end) as primary_plan_type,
        max(case when is_primary then deductible_remaining end) as primary_deductible_remaining,
        max(case when is_primary then out_of_pocket_remaining end) as primary_oop_remaining
    from {{ ref('stg_healthcare__patient_coverage') }}
    where is_active = true
    group by patient_id, hospital_id
),

-- Recent vitals (last 7 days)
recent_vitals_base as (
    select *,
        row_number() over (partition by patient_id, hospital_id
                          order by measurement_datetime desc) as rn
    from {{ ref('int_clinical__vitals_enriched') }}
    where measurement_datetime >= dateadd('day', -7, current_date())
),

recent_vitals as (
    select
        patient_id,
        hospital_id,
        count(distinct vital_id) as vital_measurements_last_7days,
        max(measurement_datetime) as last_vital_datetime,
        avg(case when is_febrile then 1 else 0 end) as febrile_rate,
        avg(case when is_hypotensive then 1 else 0 end) as hypotensive_rate,
        avg(case when is_hypoxic then 1 else 0 end) as hypoxic_rate,
        avg(bmi) as avg_bmi,
        max(case when rn = 1 then total_news_score end) as latest_news_score
    from recent_vitals_base
    group by patient_id, hospital_id
),

-- SDOH screening (most recent)
recent_sdoh as (
    select
        patient_id,
        hospital_id,
        max(screening_date) as last_sdoh_screening_date,
        max(case when rn = 1 then sdoh_risk_category end) as current_sdoh_risk_category,
        max(case when rn = 1 then total_sdoh_risk_count end) as current_sdoh_risk_count,
        max(case when rn = 1 then has_housing_risk end) as has_housing_risk,
        max(case when rn = 1 then has_food_insecurity end) as has_food_insecurity,
        max(case when rn = 1 then has_transportation_barriers end) as has_transportation_barriers
    from (
        select *,
            row_number() over (partition by patient_id, hospital_id
                              order by screening_date desc) as rn
        from {{ ref('stg_healthcare__sdoh_screenings') }}
    )
    group by patient_id, hospital_id
),

-- Encounter history (all time)
encounter_history as (
    select
        patient_id,
        hospital_id,
        count(distinct encounter_id) as total_encounters,
        count(distinct case when encounter_type = 'Emergency' then encounter_id end) as ed_visits,
        count(distinct case when encounter_type = 'Inpatient' then encounter_id end) as inpatient_admits,
        count(distinct case when is_readmission then encounter_id end) as readmissions,
        sum(total_charges) as lifetime_charges,
        max(admission_date) as last_encounter_date,
        min(admission_date) as first_encounter_date
    from {{ ref('stg_healthcare__encounters') }}
    group by patient_id, hospital_id
),

-- Medication administration (last 30 days)
recent_medications as (
    select
        patient_id,
        hospital_id,
        count(distinct admin_id) as medication_administrations_30days,
        count(distinct case when is_refused then admin_id end) as medication_refusals_30days,
        count(distinct case when adverse_reaction_flag then admin_id end) as adverse_reactions_30days,
        count(distinct medication_name) as unique_medications_30days
    from {{ ref('stg_healthcare__medication_administration') }}
    where administered_datetime >= dateadd('day', -30, current_date())
    group by patient_id, hospital_id
),

patient_profile as (
    select
        -- Patient identifiers
        p.patient_id,
        p.hospital_id,

        -- Hospital context
        h.hospital_name,
        h.hospital_type,
        h.region,

        -- Demographics
        p.age_years,
        p.age_group,
        p.gender,
        p.race,
        p.ethnicity,
        p.zip_code_3digit,
        p.primary_language,
        p.marital_status,
        p.first_encounter_date,

        -- Clinical complexity
        coalesce(ap.active_problem_count, 0) as active_problem_count,
        coalesce(ap.chronic_condition_count, 0) as chronic_condition_count,
        ap.active_diagnoses_list,

        -- Allergies
        coalesce(aa.active_allergy_count, 0) as active_allergy_count,
        coalesce(aa.life_threatening_allergy_count, 0) as life_threatening_allergy_count,
        coalesce(aa.drug_allergy_count, 0) as drug_allergy_count,
        aa.active_allergies_list,

        -- Insurance
        coalesce(cc.active_coverage_count, 0) as active_coverage_count,
        cc.primary_payer_id,
        cc.primary_plan_type,
        cc.primary_deductible_remaining,
        cc.primary_oop_remaining,

        -- Recent vitals
        rv.vital_measurements_last_7days,
        rv.last_vital_datetime,
        rv.febrile_rate,
        rv.hypotensive_rate,
        rv.hypoxic_rate,
        rv.avg_bmi,
        rv.latest_news_score,

        -- SDOH
        sdoh.last_sdoh_screening_date,
        sdoh.current_sdoh_risk_category,
        sdoh.current_sdoh_risk_count,
        sdoh.has_housing_risk,
        sdoh.has_food_insecurity,
        sdoh.has_transportation_barriers,

        -- Encounter history
        coalesce(eh.total_encounters, 0) as total_encounters,
        coalesce(eh.ed_visits, 0) as ed_visits,
        coalesce(eh.inpatient_admits, 0) as inpatient_admits,
        coalesce(eh.readmissions, 0) as readmissions,
        coalesce(eh.lifetime_charges, 0) as lifetime_charges,
        eh.last_encounter_date,

        -- Recent medications
        rm.medication_administrations_30days,
        rm.medication_refusals_30days,
        rm.adverse_reactions_30days,
        rm.unique_medications_30days,

        -- Risk stratification
        case
            when coalesce(ap.chronic_condition_count, 0) >= 3
                and coalesce(eh.ed_visits, 0) >= 2
            then 'Very High Risk'
            when coalesce(ap.chronic_condition_count, 0) >= 2
                or coalesce(eh.readmissions, 0) >= 1
            then 'High Risk'
            when coalesce(ap.chronic_condition_count, 0) >= 1
            then 'Medium Risk'
            else 'Low Risk'
        end as clinical_risk_category,

        -- Utilization category
        case
            when coalesce(eh.ed_visits, 0) >= 4 then 'Frequent ED User'
            when coalesce(eh.inpatient_admits, 0) >= 3 then 'Frequent Admits'
            when coalesce(eh.total_encounters, 0) >= 10 then 'High Utilizer'
            when coalesce(eh.total_encounters, 0) >= 5 then 'Moderate Utilizer'
            else 'Low Utilizer'
        end as utilization_category,

        -- Days since last encounter
        datediff('day', eh.last_encounter_date, current_date()) as days_since_last_encounter,

        -- Patient engagement score (0-100)
        case
            when rm.medication_refusals_30days > 0
            then greatest(0, 100 - (rm.medication_refusals_30days * 10))
            else 100
        end as patient_engagement_score,

        -- Metadata
        current_timestamp() as profile_generated_at

    from patients p
    inner join hospitals h on p.hospital_id = h.hospital_id
    left join active_problems ap
        on p.patient_id = ap.patient_id
        and p.hospital_id = ap.hospital_id
    left join active_allergies aa
        on p.patient_id = aa.patient_id
        and p.hospital_id = aa.hospital_id
    left join current_coverage cc
        on p.patient_id = cc.patient_id
        and p.hospital_id = cc.hospital_id
    left join recent_vitals rv
        on p.patient_id = rv.patient_id
        and p.hospital_id = rv.hospital_id
    left join recent_sdoh sdoh
        on p.patient_id = sdoh.patient_id
        and p.hospital_id = sdoh.hospital_id
    left join encounter_history eh
        on p.patient_id = eh.patient_id
        and p.hospital_id = eh.hospital_id
    left join recent_medications rm
        on p.patient_id = rm.patient_id
        and p.hospital_id = rm.hospital_id
)

select * from patient_profile