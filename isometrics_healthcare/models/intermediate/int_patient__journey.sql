{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'patient_journey']
  )
}}

/*
  Patient Journey Model
  Enriches encounters with patient-level aggregations and readmission logic

  Business Logic:
  - 30-day readmission: Same patient, inpatient encounter within 30 days
  - 7-day ED return: Same patient returns to ED within 7 days
  - Risk stratification based on encounter history
*/

with enriched_encounters as (
    select * from {{ ref('int_encounters__enriched') }}
),

patient_encounter_sequence as (
    -- Add encounter sequencing per patient
    select
        e.*,

        -- Previous encounter for same patient
        lag(e.encounter_id) over (
            partition by e.patient_id
            order by e.admission_date
        ) as previous_encounter_id,

        lag(e.discharge_date) over (
            partition by e.patient_id
            order by e.admission_date
        ) as previous_discharge_date,

        lag(e.encounter_type) over (
            partition by e.patient_id
            order by e.admission_date
        ) as previous_encounter_type,

        -- Days since last encounter
        datediff('day', previous_discharge_date, e.admission_date) as days_since_last_encounter,

        -- Encounter number for this patient
        row_number() over (
            partition by e.patient_id
            order by e.admission_date
        ) as patient_encounter_number,

        -- Total encounters for this patient (as of this encounter)
        count(*) over (
            partition by e.patient_id
            order by e.admission_date
            rows between unbounded preceding and current row
        ) as patient_total_encounters_to_date

    from enriched_encounters e
),

with_readmission_logic as (
    select
        p.*,

        -- 30-day readmission flag (CMS definition)
        case
            when p.encounter_type = 'Inpatient'
                and p.previous_encounter_type = 'Inpatient'
                and p.days_since_last_encounter <= 30
                and p.days_since_last_encounter > 0
            then true
            else false
        end as is_30day_readmission,

        -- 30-day return (any type)
        case
            when p.days_since_last_encounter <= 30
                and p.days_since_last_encounter > 0
            then true
            else false
        end as is_30day_return,

        -- 7-day ED return
        case
            when p.encounter_type = 'Emergency'
                and p.previous_encounter_type = 'Emergency'
                and p.days_since_last_encounter <= 7
                and p.days_since_last_encounter > 0
            then true
            else false
        end as is_7day_return,

        -- Frequent flyer (4+ ED visits in 90 days)
        count(case when p.encounter_type = 'Emergency' then 1 end) over (
            partition by p.patient_id
            order by p.admission_date
            range between interval '90 days' preceding and current row
        ) as ed_visits_last_90_days

    from patient_encounter_sequence p
),

patient_risk_scoring as (
    select
        r.*,

        -- Risk score calculation (0-100)
        least(100,
            (case when r.age_years >= 65 then 20 else 0 end) +
            (case when r.primary_diagnosis_code in ('I10', 'E11.9', 'J44.9', 'I50.9', 'N18.9', 'F32.9', 'M17.9') then 15 else 0 end) +
            (case when r.severity_level = 'Critical' then 25 else 0 end) +
            (case when r.severity_level = 'High' then 15 else 0 end) +
            (case when r.patient_total_encounters_to_date > 5 then 10 else 0 end) +
            (case when r.ed_visits_last_90_days >= 4 then 15 else 0 end)
        ) as patient_risk_score,


        -- Risk category
        case
            when patient_risk_score >= 60 then 'High Risk'
            when patient_risk_score >= 30 then 'Medium Risk'
            else 'Low Risk'
        end as patient_risk_category,

        -- Comorbidity flag (chronic condition + high severity)
        case
            when r.is_chronic and r.severity_level in ('High', 'Critical')
            then true
            else false
        end as has_comorbidity

    from with_readmission_logic r
)

select * from patient_risk_scoring