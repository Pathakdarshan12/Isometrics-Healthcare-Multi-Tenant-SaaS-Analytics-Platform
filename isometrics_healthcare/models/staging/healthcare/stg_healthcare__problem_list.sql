{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'clinical', 'diagnoses'],
    meta={
      'contains_phi': true,
      'phi_fields': ['onset_date', 'resolution_date']
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_problem_list') }}
),

renamed as (
    select
        -- Primary Key
        problem_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        patient_id,
        documented_by_provider_id,

        -- Diagnosis details
        diagnosis_code,
        diagnosis_description,

        -- Status tracking
        problem_status,
        onset_date,
        resolution_date,
        last_reviewed_date,

        -- Clinical metadata
        severity,
        is_chronic,
        is_primary_diagnosis,

        -- Documentation
        documentation_date,
        clinical_notes,

        -- Flags
        case when problem_status = 'ACTIVE' then true else false end as is_active,
        case when problem_status = 'RESOLVED' then true else false end as is_resolved,

        -- Duration calculations
        case
            when problem_status = 'RESOLVED' and resolution_date is not null
            then datediff('day', onset_date, resolution_date)
            when problem_status = 'ACTIVE'
            then datediff('day', onset_date, current_date())
            else null
        end as problem_duration_days,

        case
            when last_reviewed_date is not null
            then datediff('day', last_reviewed_date, current_date())
            else null
        end as days_since_last_review,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed