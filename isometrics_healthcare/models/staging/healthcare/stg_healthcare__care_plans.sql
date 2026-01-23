{{
  config(
    materialized='view',
    secure = true,
    tags=['staging', 'bronze', 'clinical', 'care_plans'],
    meta={
      'contains_phi': true,
      'phi_fields': ['start_date', 'target_date', 'completion_date']
    },
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

with source as (
    select *
    from {{ source('healthcare', 'raw_care_plans') }}
),

renamed as (
    select
        -- Primary Key
        care_plan_id,

        -- Foreign Keys (🔒 critical for RLS)
        hospital_id,
        patient_id,
        encounter_id,
        created_by_provider_id,

        -- Care Plan Content
        problem_description,
        goal_description,
        intervention_description,

        -- Status & Dates
        plan_status,
        start_date,
        target_date,
        completion_date,
        last_evaluated_date,

        -- Care Team
        assigned_to_provider_ids,

        -- Progress Tracking
        progress_notes,

        -- Flags derived from plan_status
        case when plan_status = 'ACTIVE' then true else false end as is_active_plan,
        case when plan_status = 'COMPLETED' then true else false end as is_completed_plan,
        case when plan_status = 'DISCONTINUED' then true else false end as is_discontinued_plan,

        -- Duration Metrics
        case
            when plan_status = 'COMPLETED' and completion_date is not null
                then datediff('day', start_date, completion_date)
            when plan_status = 'ACTIVE' and start_date is not null
                then datediff('day', start_date, current_date())
            else null
        end as plan_duration_days,

        case
            when target_date is not null
                then datediff('day', current_date(), target_date)
            else null
        end as days_to_target,

        case
            when last_evaluated_date is not null
                then datediff('day', last_evaluated_date, current_date())
            else null
        end as days_since_last_evaluation,

        -- Compliance Flags
        case
            when plan_status = 'ACTIVE'
             and last_evaluated_date is not null
             and datediff('day', last_evaluated_date, current_date()) > 90
            then true
            else false
        end as overdue_for_evaluation,

        case
            when plan_status = 'ACTIVE'
             and target_date is not null
             and current_date() > target_date
            then true
            else false
        end as past_target_date,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed