{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'clinical', 'lab_results']
  )
}}

with lab_results as (
    select * from {{ ref('stg_healthcare__clinical_results') }}
    where result_type = 'LAB'
),

lab_orders as (
    select * from {{ ref('stg_healthcare__clinical_orders') }}
    where order_type = 'LAB'
),

encounters as (
    select * from {{ ref('stg_healthcare__encounters') }}
),

patients as (
    select * from {{ ref('stg_healthcare__patients') }}
),

providers as (
    select * from {{ ref('stg_healthcare__providers') }}
),

hospitals as (
    select * from {{ ref('stg_healthcare__hospitals') }}
),

-- Get previous result for trending
lab_with_previous as (
    select
        lr.*,
        lag(lr.result_value_numeric) over (
            partition by lr.patient_id, lr.test_code
            order by lr.result_datetime
        ) as previous_result_value,

        lag(lr.result_datetime) over (
            partition by lr.patient_id, lr.test_code
            order by lr.result_datetime
        ) as previous_result_datetime,

        row_number() over (
            partition by lr.patient_id, lr.test_code
            order by lr.result_datetime
        ) as result_sequence

    from lab_results lr
),

enriched as (
    select
        -- Identifiers
        lr.result_id,
        lr.hospital_id,
        lr.order_id,
        lr.patient_id,
        lr.encounter_id,

        -- Hospital context
        h.hospital_name,
        h.hospital_type,
        h.region,

        -- Patient demographics
        p.age_years,
        p.age_group,
        p.gender,

        -- Encounter context
        e.encounter_type,
        e.admission_date,
        e.primary_diagnosis_code,

        -- Ordering provider
        ord_prov.provider_full_name as ordering_provider_name,
        ord_prov.specialty as ordering_provider_specialty,

        -- Interpreting provider
        int_prov.provider_full_name as interpreting_provider_name,

        -- Test identification
        lr.test_code,
        lr.test_name,
        lr.component_code,
        lr.component_name,

        -- Result values
        lr.result_value,
        lr.result_value_numeric,
        lr.result_units,
        lr.reference_range_low,
        lr.reference_range_high,
        lr.abnormal_flag,

        -- Timing
        lr.result_datetime,
        lr.collected_datetime,
        lr.resulted_datetime,

        -- Status
        lr.result_status,
        lr.performing_lab,

        -- Flags
        lr.is_abnormal,
        lr.is_high,
        lr.is_low,
        lr.is_final,
        lr.is_preliminary,

        -- Turnaround time
        lr.turnaround_time_hours,
        lo.completion_time_hours as order_completion_hours,

        -- Out of range analysis
        lr.out_of_range_value,
        case
            when lr.out_of_range_value > 0
            then (lr.out_of_range_value * 100.0) / nullif(lr.reference_range_high, 0)
            else 0
        end as percent_above_range,

        -- Previous result tracking
        lr.previous_result_value,
        lr.previous_result_datetime,
        lr.result_sequence,

        -- Result change analysis
        lr.result_value_numeric - lr.previous_result_value as result_change,
        case
            when lr.previous_result_value is not null and lr.previous_result_value != 0
            then ((lr.result_value_numeric - lr.previous_result_value) * 100.0) / lr.previous_result_value
            else null
        end as result_change_pct,

        -- Time between results
        datediff('day', lr.previous_result_datetime, lr.result_datetime) as days_since_previous_result,

        -- Trend direction
        case
            when lr.result_value_numeric > lr.previous_result_value then 'Increasing'
            when lr.result_value_numeric < lr.previous_result_value then 'Decreasing'
            when lr.result_value_numeric = lr.previous_result_value then 'Stable'
            else 'First Result'
        end as trend_direction,

        -- Critical value flags (simplified examples - should use reference database)
        case
            when lower(lr.test_name) like '%glucose%' and lr.result_value_numeric < 40 then true
            when lower(lr.test_name) like '%glucose%' and lr.result_value_numeric > 500 then true
            when lower(lr.test_name) like '%potassium%' and lr.result_value_numeric < 2.5 then true
            when lower(lr.test_name) like '%potassium%' and lr.result_value_numeric > 6.5 then true
            when lower(lr.test_name) like '%sodium%' and lr.result_value_numeric < 120 then true
            when lower(lr.test_name) like '%sodium%' and lr.result_value_numeric > 160 then true
            when lower(lr.test_name) like '%hemoglobin%' and lr.result_value_numeric < 6 then true
            when lower(lr.test_name) like '%creatinine%' and lr.result_value_numeric > 10 then true
            when lower(lr.test_name) like '%troponin%' and lr.result_value_numeric > 0.5 then true
            else false
        end as is_critical_value,

        -- Common lab panel identification
        case
            when lower(lr.test_name) like any ('%cbc%', '%hemoglobin%', '%hematocrit%', '%platelet%', '%wbc%')
            then 'Complete Blood Count'
            when lower(lr.test_name) like any ('%sodium%', '%potassium%', '%chloride%', '%bicarb%', '%glucose%')
            then 'Basic Metabolic Panel'
            when lower(lr.test_name) like any ('%cmp%', '%albumin%', '%calcium%', '%protein%')
            then 'Comprehensive Metabolic Panel'
            when lower(lr.test_name) like any ('%ast%', '%alt%', '%bilirubin%', '%alkaline%')
            then 'Liver Function Panel'
            when lower(lr.test_name) like any ('%lipid%', '%cholesterol%', '%triglyceride%', '%hdl%', '%ldl%')
            then 'Lipid Panel'
            when lower(lr.test_name) like '%troponin%'
            then 'Cardiac Marker'
            when lower(lr.test_name) like any ('%pt%', '%inr%', '%ptt%', '%aptt%')
            then 'Coagulation Panel'
            else 'Other'
        end as lab_panel_category,

        -- Encounter day of result
        datediff('day', e.admission_date, lr.result_datetime) as encounter_day_of_result,

        -- Metadata
        lr.loaded_at_timestamp

    from lab_with_previous lr
    inner join hospitals h on lr.hospital_id = h.hospital_id
    inner join encounters e on lr.encounter_id = e.encounter_id
    inner join patients p on lr.patient_id = p.patient_id
    left join providers int_prov on lr.interpreting_provider_id = int_prov.provider_id
    left join lab_orders lo on lr.order_id = lo.order_id
    left join providers ord_prov on lo.provider_id = ord_prov.provider_id
)

select * from enriched