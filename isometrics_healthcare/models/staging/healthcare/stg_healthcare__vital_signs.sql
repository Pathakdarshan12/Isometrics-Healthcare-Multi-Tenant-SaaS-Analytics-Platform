{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'clinical', 'vitals'],
    meta={
      'contains_phi': true,
      'phi_fields': ['measurement_datetime']
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_vital_signs') }}
),

renamed as (
    select
        -- Primary Key
        vital_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        encounter_id,
        patient_id,

        -- Measurement context
        measurement_datetime,
        position,
        measured_by_role,

        -- Standard vitals
        temperature_f,
        heart_rate_bpm,
        respiratory_rate,
        systolic_bp,
        diastolic_bp,
        oxygen_saturation_pct,
        weight_kg,
        height_cm,
        bmi,
        pain_score,
        map_mmhg,

        -- Clinical flags based on vitals
        case when temperature_f > 100.4 then true else false end as is_febrile,
        case when temperature_f < 95.0 then true else false end as is_hypothermic,
        case when heart_rate_bpm > 100 then true else false end as is_tachycardic,
        case when heart_rate_bpm < 60 then true else false end as is_bradycardic,
        case when respiratory_rate > 20 then true else false end as is_tachypneic,
        case when respiratory_rate < 12 then true else false end as is_bradypneic,
        case when systolic_bp > 140 or diastolic_bp > 90 then true else false end as is_hypertensive,
        case when systolic_bp < 90 or diastolic_bp < 60 then true else false end as is_hypotensive,
        case when oxygen_saturation_pct < 90 then true else false end as is_hypoxic,
        case when bmi >= 30 then true else false end as is_obese,
        case when pain_score >= 7 then true else false end as has_severe_pain,

        -- Early Warning Score (NEWS) components
        case
            when respiratory_rate <= 8 then 3
            when respiratory_rate between 9 and 11 then 1
            when respiratory_rate between 21 and 24 then 2
            when respiratory_rate >= 25 then 3
            else 0
        end as news_respiratory_score,

        case
            when oxygen_saturation_pct <= 91 then 3
            when oxygen_saturation_pct between 92 and 93 then 2
            when oxygen_saturation_pct between 94 and 95 then 1
            else 0
        end as news_oxygen_score,

        case
            when systolic_bp <= 90 then 3
            when systolic_bp between 91 and 100 then 2
            when systolic_bp between 101 and 110 then 1
            when systolic_bp >= 220 then 3
            else 0
        end as news_systolic_score,

        case
            when heart_rate_bpm <= 40 then 3
            when heart_rate_bpm between 41 and 50 then 1
            when heart_rate_bpm between 91 and 110 then 1
            when heart_rate_bpm between 111 and 130 then 2
            when heart_rate_bpm >= 131 then 3
            else 0
        end as news_heart_rate_score,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed