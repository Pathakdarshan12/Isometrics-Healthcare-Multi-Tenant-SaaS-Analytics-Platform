{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'care_coordination', 'referrals'],
    meta={
      'contains_phi': false
    }
  )
}}

with source as (
    select *
    from {{ source('healthcare', 'raw_referrals') }}
),

renamed as (
    select
        -- Primary Key
        referral_id,

        -- Foreign Keys (🔒 critical for RLS)
        hospital_id,
        patient_id,
        encounter_id,

        -- Providers / Destination
        referring_provider_id,
        referred_to_provider_id,
        referred_to_facility,

        -- Referral Details
        referral_type,
        specialty,
        urgency,
        reason_for_referral,

        -- Clinical Context
        diagnosis_codes,

        -- Status & Dates
        referral_status,
        referral_date,
        appointment_date,
        completion_date,

        -- Follow-up Tracking
        follow_up_required,
        follow_up_completed,

        -- Status Flags
        case when referral_status = 'COMPLETED' then true else false end as is_completed,
        case when referral_status = 'PENDING' then true else false end as is_pending,
        case when referral_status = 'CANCELLED' then true else false end as is_cancelled,
        case when urgency = 'URGENT' then true else false end as is_urgent,

        -- Timing Metrics
        case
            when appointment_date is not null
            then datediff('day', referral_date, appointment_date)
            else null
        end as days_to_appointment,

        case
            when completion_date is not null
            then datediff('day', referral_date, completion_date)
            else null
        end as days_to_completion,

        -- Follow-up Flags
        case
            when follow_up_required and not follow_up_completed
            then true
            else false
        end as follow_up_overdue,

        -- Overdue Scheduling Flag
        case
            when referral_status = 'PENDING'
             and appointment_date is null
             and datediff('day', referral_date, current_date()) > 14
            then true
            else false
        end as overdue_for_appointment,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed