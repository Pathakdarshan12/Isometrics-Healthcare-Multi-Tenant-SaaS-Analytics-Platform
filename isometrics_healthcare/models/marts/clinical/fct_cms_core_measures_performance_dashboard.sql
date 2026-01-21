{{
  config(
    materialized='table',
    tags=['marts', 'clinical_quality', 'cms_measures', 'regulatory'],
    cluster_by=['hospital_id', 'reporting_quarter']
  )
}}

/*
  CMS Core Measures Performance Dashboard
  Tracks hospital performance on CMS quality measures including:
  - Sepsis (SEP-1)
  - Acute Myocardial Infarction (AMI)
  - Stroke
  - Pneumonia
  - Heart Failure
*/

with encounters as (
    select * from {{ ref('int_encounters__enriched') }}
),

vitals as (
    select * from {{ ref('int_clinical__vitals_enriched') }}
),

orders as (
    select * from {{ ref('int_clinical__orders_enriched') }}
),

-- Sepsis bundle compliance (SEP-1)
sepsis_cohort as (
    select
        e.hospital_id,
        date_trunc('quarter', e.admission_date) as reporting_quarter,
        e.encounter_id,

        -- Sepsis indicators (simplified)
        case
            when v.sepsis_alert = true then true
            when e.primary_diagnosis_code like 'A41%' then true  -- Sepsis ICD-10
            else false
        end as is_sepsis_case,

        -- Check for early antibiotic order (within 3 hours)
        case
            when exists (
                select 1 from orders o
                where o.encounter_id = e.encounter_id
                and o.order_type = 'MEDICATION'
                and lower(o.medication_name) like any ('%antibiotic%', '%ceftriaxone%', '%vancomycin%')
                and o.encounter_day_of_order = 0  -- First day
                and o.completion_time_hours <= 3
            ) then true
            else false
        end as early_antibiotics_met,

        -- Check for lactate measurement
        case
            when exists (
                select 1 from orders o
                where o.encounter_id = e.encounter_id
                and o.order_type = 'LAB'
                and lower(o.order_description) like '%lactate%'
                and o.encounter_day_of_order = 0
            ) then true
            else false
        end as lactate_measured,

        -- Check for blood cultures
        case
            when exists (
                select 1 from orders o
                where o.encounter_id = e.encounter_id
                and o.order_type = 'LAB'
                and lower(o.order_description) like '%blood culture%'
                and o.encounter_day_of_order = 0
            ) then true
            else false
        end as blood_cultures_obtained

    from encounters e
    left join vitals v on e.encounter_id = v.encounter_id
    where e.encounter_type in ('Emergency', 'Inpatient')
),

-- AMI measures (simplified)
ami_cohort as (
    select
        e.hospital_id,
        date_trunc('quarter', e.admission_date) as reporting_quarter,
        e.encounter_id,

        case
            when e.primary_diagnosis_code like 'I21%' then true  -- AMI ICD-10
            else false
        end as is_ami_case,

        -- Check for aspirin within 24 hours
        case
            when exists (
                select 1 from orders o
                where o.encounter_id = e.encounter_id
                and o.order_type = 'MEDICATION'
                and lower(o.medication_name) like '%aspirin%'
                and o.encounter_day_of_order <= 1
            ) then true
            else false
        end as aspirin_received,

        -- Check for beta blocker
        case
            when exists (
                select 1 from orders o
                where o.encounter_id = e.encounter_id
                and o.order_type = 'MEDICATION'
                and lower(o.medication_name) like any ('%metoprolol%', '%atenolol%', '%carvedilol%')
            ) then true
            else false
        end as beta_blocker_received

    from encounters e
    where e.encounter_type in ('Emergency', 'Inpatient')
),

-- Aggregate by hospital and quarter
sepsis_performance as (
    select
        hospital_id,
        reporting_quarter,
        'SEP-1' as measure_code,
        'Sepsis Bundle' as measure_name,

        count(distinct case when is_sepsis_case then encounter_id end) as denominator,
        count(distinct case when is_sepsis_case and early_antibiotics_met and lactate_measured and blood_cultures_obtained
              then encounter_id end) as numerator,

        case
            when count(distinct case when is_sepsis_case then encounter_id end) > 0
            then (count(distinct case when is_sepsis_case and early_antibiotics_met and lactate_measured and blood_cultures_obtained
                  then encounter_id end) * 100.0) /
                 count(distinct case when is_sepsis_case then encounter_id end)
            else 0
        end as performance_rate_pct,

        50.0 as cms_target_pct  -- CMS target for SEP-1

    from sepsis_cohort
    group by hospital_id, reporting_quarter
),

ami_performance as (
    select
        hospital_id,
        reporting_quarter,
        'AMI-2' as measure_code,
        'AMI: Aspirin at Arrival' as measure_name,

        count(distinct case when is_ami_case then encounter_id end) as denominator,
        count(distinct case when is_ami_case and aspirin_received
              then encounter_id end) as numerator,

        case
            when count(distinct case when is_ami_case then encounter_id end) > 0
            then (count(distinct case when is_ami_case and aspirin_received
                  then encounter_id end) * 100.0) /
                 count(distinct case when is_ami_case then encounter_id end)
            else 0
        end as performance_rate_pct,

        95.0 as cms_target_pct

    from ami_cohort
    group by hospital_id, reporting_quarter
),

-- Readmission measures (simplified)
readmission_performance as (
    select
        e.hospital_id,
        date_trunc('quarter', e.admission_date) as reporting_quarter,
        'READM-30' as measure_code,
        '30-Day All-Cause Readmission' as measure_name,

        count(distinct case when e.encounter_type = 'Inpatient' then e.encounter_id end) as denominator,
        count(distinct case when e.is_readmission then e.encounter_id end) as numerator,

        {{ calculate_readmission_rate('is_readmission', 'encounter_type') }} as performance_rate_pct,

        15.0 as cms_target_pct  -- Lower is better for readmissions

    from encounters e
    group by e.hospital_id, date_trunc('quarter', e.admission_date)
),

-- Combine all measures
all_measures as (
    select * from sepsis_performance
    union all
    select * from ami_performance
    union all
    select * from readmission_performance
),

with_status as (
    select
        *,

        -- Performance status vs CMS target
        case
            when measure_code = 'READM-30' then
                case
                    when performance_rate_pct <= cms_target_pct then 'Meets Target'
                    when performance_rate_pct <= cms_target_pct * 1.1 then 'Near Target'
                    else 'Below Target'
                end
            else
                case
                    when performance_rate_pct >= cms_target_pct then 'Meets Target'
                    when performance_rate_pct >= cms_target_pct * 0.9 then 'Near Target'
                    else 'Below Target'
                end
        end as performance_status,

        -- Gap to target
        case
            when measure_code = 'READM-30'
            then cms_target_pct - performance_rate_pct  -- Positive gap is good for readmissions
            else performance_rate_pct - cms_target_pct  -- Positive gap is good for quality measures
        end as gap_to_target_pct,

        current_timestamp() as _dbt_loaded_at

    from all_measures
    where denominator >= 25
)

select * from with_status