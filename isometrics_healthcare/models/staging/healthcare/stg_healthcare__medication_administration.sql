{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'clinical', 'medications'],
    meta={
      'contains_phi': true,
      'phi_fields': ['scheduled_datetime', 'administered_datetime']
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_medication_administration') }}
),

renamed as (
    select
        -- Primary Key
        admin_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        encounter_id,
        patient_id,
        order_id,
        administered_by_provider_id,
        witnessed_by_provider_id,

        -- Medication details
        medication_name,
        dose,
        route,

        -- Administration tracking
        scheduled_datetime,
        administered_datetime,
        administration_status,
        refusal_reason,
        hold_reason,

        -- Verification
        barcode_scanned,

        -- Adverse reactions
        adverse_reaction_flag,
        reaction_description,

        -- Flags
        case when administration_status = 'GIVEN' then true else false end as is_given,
        case when administration_status = 'REFUSED' then true else false end as is_refused,
        case when administration_status = 'HELD' then true else false end as is_held,
        case when administration_status = 'MISSED' then true else false end as is_missed,
        case when barcode_scanned = true then true else false end as is_verified,
        case when witnessed_by_provider_id is not null then true else false end as is_witnessed,

        -- Timing calculations
        case
            when administered_datetime is not null and scheduled_datetime is not null
            then datediff('minute', scheduled_datetime, administered_datetime)
            else null
        end as administration_delay_minutes,

        case
            when datediff('minute', scheduled_datetime, administered_datetime) > 60
            then true
            else false
        end as is_late_administration,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed