{{
  config(
    materialized='view',
    tags=['staging', 'bronze', 'financial', 'insurance'],
    meta={
      'contains_phi': true,
      'phi_fields': ['policy_number', 'subscriber_id', 'subscriber_name'],
      'owner': 'financial-analytics@company.com'
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_patient_coverage') }}
),

renamed as (
    select
        -- Primary Key
        coverage_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        patient_id,
        payer_id,

        -- Policy details
        policy_number,
        group_number,
        subscriber_id,
        subscriber_name,
        subscriber_relationship,

        -- Coverage period
        effective_date,
        termination_date,
        coverage_status,

        -- Coverage type
        plan_type,
        coverage_level,

        -- Financial
        deductible_amount,
        deductible_met_amount,
        out_of_pocket_max,
        out_of_pocket_met,
        copay_amount,
        coinsurance_pct,

        -- Priority
        coverage_priority,

        -- Flags
        case when coverage_status = 'ACTIVE' then true else false end as is_active,
        case when coverage_priority = 1 then true else false end as is_primary,
        case when coverage_priority = 2 then true else false end as is_secondary,
        case when subscriber_relationship = 'SELF' then true else false end as is_self_insured,

        -- Financial calculations
        deductible_amount - deductible_met_amount as deductible_remaining,
        out_of_pocket_max - out_of_pocket_met as out_of_pocket_remaining,

        case
            when deductible_amount > 0
            then (deductible_met_amount * 100.0) / deductible_amount
            else 0
        end as deductible_met_pct,

        case
            when out_of_pocket_max > 0
            then (out_of_pocket_met * 100.0) / out_of_pocket_max
            else 0
        end as out_of_pocket_met_pct,

        -- Coverage duration
        case
            when coverage_status = 'ACTIVE'
            then datediff('day', effective_date, current_date())
            when termination_date is not null
            then datediff('day', effective_date, termination_date)
            else null
        end as coverage_duration_days,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed