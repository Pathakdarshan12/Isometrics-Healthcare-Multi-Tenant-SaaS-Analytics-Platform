{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'financial', 'prior_auth'],
    meta={
      'contains_phi': false
    }
  )
}}

with source as (
    select *
    from {{ source('healthcare', 'raw_prior_authorizations') }}
),

renamed as (
    select
        -- Primary Key
        auth_id,

        -- Foreign Keys (🔒 critical for RLS)
        hospital_id,
        patient_id,
        encounter_id,
        payer_id,

        -- Authorization Identifiers
        auth_number,
        auth_type,

        -- Service Details
        service_code,
        service_description,

        -- Clinical Context
        diagnosis_codes,
        clinical_notes,

        -- Status & Dates
        auth_status,
        request_date,
        decision_date,
        effective_date,
        expiration_date,

        -- Units Tracking
        units_authorized,
        units_used,
        units_remaining,

        -- Denial Info
        denial_reason,

        -- Flags derived from auth_status
        case when auth_status = 'APPROVED' then true else false end as is_approved,
        case when auth_status = 'DENIED' then true else false end as is_denied,
        case when auth_status = 'PENDING' then true else false end as is_pending,

        -- Units Utilization Metrics
        case
            when units_authorized is not null
             and units_authorized > 0
            then (units_used * 100.0) / units_authorized
            else null
        end as units_utilization_pct,

        case
            when units_remaining = 0
             and units_authorized is not null
            then true
            else false
        end as is_fully_utilized,

        -- Timing Metrics
        case
            when decision_date is not null
            then datediff('day', request_date, decision_date)
            else null
        end as days_to_decision,

        case
            when effective_date is not null
             and expiration_date is not null
            then datediff('day', effective_date, expiration_date)
            else null
        end as auth_duration_days,

        case
            when expiration_date is not null
            then datediff('day', current_date(), expiration_date)
            else null
        end as days_to_expiration,

        -- Expiration Flags
        case
            when expiration_date is not null
             and current_date() > expiration_date
            then true
            else false
        end as is_expired,

        case
            when expiration_date is not null
             and datediff('day', current_date(), expiration_date) between 0 and 30
            then true
            else false
        end as expiring_soon,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed