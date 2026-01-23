{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'quality', 'cms_measures'],
    meta={
      'contains_phi': false
    }
  )
}}

with source as (
    select *
    from {{ source('healthcare', 'raw_quality_measures') }}
),

renamed as (
    select
        -- Primary Key
        measure_id,

        -- Foreign Keys (🔒 critical for RLS)
        hospital_id,
        encounter_id,
        patient_id,

        -- Measure Identification
        measure_code,
        measure_name,
        measure_category,
        metric_component,

        -- Eligibility
        numerator_eligible,
        denominator_eligible,

        -- Exclusions
        exclusion_applied,
        exclusion_reason,

        -- Timing / Performance Metrics
        door_to_antibiotic_minutes,
        door_to_balloon_minutes,
        door_to_needle_minutes,

        -- Component-Level Measurement
        component_value,
        component_timestamp,

        -- Compliance
        compliance_flag,

        -- Reporting
        reporting_quarter,
        reporting_year,

        -- Derived Eligibility Flags
        case
            when denominator_eligible
             and not exclusion_applied
            then true
            else false
        end as is_measure_eligible,

        case
            when numerator_eligible
             and denominator_eligible
             and not exclusion_applied
            then true
            else false
        end as is_numerator_met,

        -- Overall Performance Flag
        case
            when compliance_flag = true
            then true
            else false
        end as is_compliant,

        -- Gap in Care Identification
        case
            when denominator_eligible
             and not exclusion_applied
             and not numerator_eligible
            then true
            else false
        end as gap_in_care,

        -- Time-to-Treatment Quality Flags
        case
            when door_to_antibiotic_minutes is not null
             and door_to_antibiotic_minutes <= 60
            then true
            else false
        end as met_antibiotic_timeliness,

        case
            when door_to_balloon_minutes is not null
             and door_to_balloon_minutes <= 90
            then true
            else false
        end as met_balloon_timeliness,

        case
            when door_to_needle_minutes is not null
             and door_to_needle_minutes <= 30
            then true
            else false
        end as met_needle_timeliness,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed
