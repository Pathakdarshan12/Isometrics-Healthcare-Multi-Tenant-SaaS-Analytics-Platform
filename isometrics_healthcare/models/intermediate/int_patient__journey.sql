{{
  config(
    materialized='view',
    tags=['intermediate', 'silver', 'patient_journey']
  )
}}

with enriched_encounters as (
    select * from {{ ref('int_encounters__enriched') }}
),

-- Calculate patient-level metrics for risk stratification
patient_history as (
    select
        patient_id,
        hospital_id,
        count(distinct encounter_id) as total_encounters,
        count(distinct case when encounter_type = 'Inpatient' then encounter_id end) as inpatient_count,
        count(distinct case when encounter_type = 'Emergency' then encounter_id end) as emergency_count,
        sum(case when is_chronic then 1 else 0 end) as chronic_condition_count,
        avg(length_of_stay) as avg_los,
        sum(total_charges) as lifetime_charges
    from enriched_encounters
    group by patient_id, hospital_id
),

-- Add 30-day and 7-day return flags
with_readmission_windows as (
    select
        e.*,

        -- Patient history metrics
        ph.total_encounters as patient_total_encounters,
        ph.inpatient_count as patient_inpatient_count,
        ph.emergency_count as patient_emergency_count,
        ph.chronic_condition_count as patient_chronic_conditions,

        -- Risk category
        case
            when ph.chronic_condition_count >= 3 then 'High Risk'
            when ph.chronic_condition_count >= 1 then 'Medium Risk'
            else 'Low Risk'
        end as patient_risk_category,

        -- Look back for previous discharge in last 30 days
        lag(discharge_date) over (
            partition by e.patient_id
            order by e.admission_date
        ) as previous_discharge_date,

        -- Calculate days since last discharge
        datediff('day', previous_discharge_date, e.admission_date) as days_since_last_discharge,

        -- 30-day return flag
        case
            when days_since_last_discharge between 1 and 30 then true
            else false
        end as is_30day_return,

        -- 7-day return flag (for ED metrics)
        case
            when days_since_last_discharge between 1 and 7 then true
            else false
        end as is_7day_return

    from enriched_encounters e
    left join patient_history ph
        on e.patient_id = ph.patient_id
        and e.hospital_id = ph.hospital_id
)

select * from with_readmission_windows