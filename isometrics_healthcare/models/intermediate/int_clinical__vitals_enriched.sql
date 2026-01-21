{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'clinical', 'vitals']
  )
}}

with vitals as (
    select * from {{ ref('stg_healthcare__vital_signs') }}
),

encounters as (
    select * from {{ ref('stg_healthcare__encounters') }}
),

patients as (
    select * from {{ ref('stg_healthcare__patients') }}
),

hospitals as (
    select * from {{ ref('stg_healthcare__hospitals') }}
),

-- Calculate rolling vitals trends
vitals_with_trends as (
    select
        v.*,

        -- Previous vital values for trend analysis
        lag(v.temperature_f) over (
            partition by v.patient_id, v.encounter_id
            order by v.measurement_datetime
        ) as previous_temperature_f,

        lag(v.heart_rate_bpm) over (
            partition by v.patient_id, v.encounter_id
            order by v.measurement_datetime
        ) as previous_heart_rate_bpm,

        lag(v.systolic_bp) over (
            partition by v.patient_id, v.encounter_id
            order by v.measurement_datetime
        ) as previous_systolic_bp,

        lag(v.oxygen_saturation_pct) over (
            partition by v.patient_id, v.encounter_id
            order by v.measurement_datetime
        ) as previous_oxygen_saturation_pct,

        -- Time since last measurement
        lag(v.measurement_datetime) over (
            partition by v.patient_id, v.encounter_id
            order by v.measurement_datetime
        ) as previous_measurement_datetime,

        -- Row number for sequence tracking
        row_number() over (
            partition by v.patient_id, v.encounter_id
            order by v.measurement_datetime
        ) as measurement_sequence

    from vitals v
),

enriched as (
    select
        -- Identifiers
        vt.vital_id,
        vt.hospital_id,
        vt.encounter_id,
        vt.patient_id,

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

        -- Measurement context
        vt.measurement_datetime,
        vt.position,
        vt.measured_by_role,
        vt.measurement_sequence,

        -- Vital signs
        vt.temperature_f,
        vt.heart_rate_bpm,
        vt.respiratory_rate,
        vt.systolic_bp,
        vt.diastolic_bp,
        vt.oxygen_saturation_pct,
        vt.weight_kg,
        vt.height_cm,
        vt.bmi,
        vt.pain_score,
        vt.map_mmhg,

        -- Clinical flags
        vt.is_febrile,
        vt.is_hypothermic,
        vt.is_tachycardic,
        vt.is_bradycardic,
        vt.is_tachypneic,
        vt.is_bradypneic,
        vt.is_hypertensive,
        vt.is_hypotensive,
        vt.is_hypoxic,
        vt.is_obese,
        vt.has_severe_pain,

        -- NEWS scores
        vt.news_respiratory_score,
        vt.news_oxygen_score,
        vt.news_systolic_score,
        vt.news_heart_rate_score,

        -- Total NEWS score
        vt.news_respiratory_score +
        vt.news_oxygen_score +
        vt.news_systolic_score +
        vt.news_heart_rate_score as total_news_score,

        -- NEWS risk category
        case
            when (vt.news_respiratory_score + vt.news_oxygen_score +
                  vt.news_systolic_score + vt.news_heart_rate_score) >= 7 then 'High Risk'
            when (vt.news_respiratory_score + vt.news_oxygen_score +
                  vt.news_systolic_score + vt.news_heart_rate_score) >= 5 then 'Medium Risk'
            when (vt.news_respiratory_score + vt.news_oxygen_score +
                  vt.news_systolic_score + vt.news_heart_rate_score) >= 3 then 'Low Risk'
            else 'Normal'
        end as news_risk_category,

        -- Trend analysis
        vt.previous_temperature_f,
        vt.previous_heart_rate_bpm,
        vt.previous_systolic_bp,
        vt.previous_oxygen_saturation_pct,
        vt.previous_measurement_datetime,

        -- Time since last measurement
        datediff('minute', vt.previous_measurement_datetime, vt.measurement_datetime) as minutes_since_last_vitals,

        -- Calculate vital sign changes
        vt.temperature_f - vt.previous_temperature_f as temperature_change,
        vt.heart_rate_bpm - vt.previous_heart_rate_bpm as heart_rate_change,
        vt.systolic_bp - vt.previous_systolic_bp as systolic_bp_change,
        vt.oxygen_saturation_pct - vt.previous_oxygen_saturation_pct as oxygen_sat_change,

        -- Rapid deterioration flags
        case
            when vt.temperature_f - vt.previous_temperature_f > 2.0 then true
            when vt.heart_rate_bpm - vt.previous_heart_rate_bpm > 30 then true
            when vt.systolic_bp - vt.previous_systolic_bp < -30 then true
            when vt.oxygen_saturation_pct - vt.previous_oxygen_saturation_pct < -5 then true
            else false
        end as rapid_deterioration_flag,

        -- Time in encounter when measured
        datediff('day', e.admission_date, vt.measurement_datetime) as encounter_day_of_measurement,
        datediff('hour', e.admission_date, vt.measurement_datetime) as encounter_hour_of_measurement,

        -- Composite alert flags
        case
            when vt.is_hypotensive and vt.is_tachycardic and vt.is_hypoxic then true
            else false
        end as sepsis_alert,

        case
            when vt.is_hypertensive and vt.has_severe_pain then true
            else false
        end as hypertensive_crisis_alert,

        case
            when vt.is_hypoxic and vt.is_tachypneic then true
            else false
        end as respiratory_distress_alert,

        -- Metadata
        vt.loaded_at_timestamp

    from vitals_with_trends vt
    inner join hospitals h on vt.hospital_id = h.hospital_id
    inner join encounters e on vt.encounter_id = e.encounter_id
    inner join patients p on vt.patient_id = p.patient_id
)

select * from enriched