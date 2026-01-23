{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'clinical', 'sdoh', 'population_health'],
    meta={
      'contains_phi': true,
      'phi_fields': ['screening_date'],
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_sdoh_screenings') }}
),

renamed as (
    select
        -- Primary Key
        screening_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        patient_id,
        encounter_id,

        -- Screening context
        screening_date,
        screening_tool_name,

        -- Housing
        housing_status,
        housing_concerns,

        -- Food security
        food_insecurity_flag,
        difficulty_affording_food,

        -- Transportation
        transportation_barriers,

        -- Financial strain
        difficulty_paying_utilities,
        difficulty_affording_medications,

        -- Social isolation
        social_isolation_score,

        -- Safety
        safety_concerns,
        intimate_partner_violence_screen,

        -- Employment
        employment_status,

        -- Education
        highest_education_level,
        health_literacy_score,

        -- Referrals
        referrals_text,

        -- Risk flags (any positive screen)
        case when housing_concerns = true then true else false end as has_housing_risk,
        case when food_insecurity_flag = true or difficulty_affording_food = true then true else false end as has_food_insecurity,
        case when transportation_barriers = true then true else false end as has_transportation_barriers,
        case when difficulty_paying_utilities = true or difficulty_affording_medications = true then true else false end as has_financial_strain,
        case when social_isolation_score >= 6 then true else false end as has_high_social_isolation,
        case when safety_concerns = true or intimate_partner_violence_screen = true then true else false end as has_safety_concerns,

        -- Composite risk score (count of positive screens)
        (case when housing_concerns = true then 1 else 0 end) +
        (case when food_insecurity_flag = true then 1 else 0 end) +
        (case when transportation_barriers = true then 1 else 0 end) +
        (case when difficulty_paying_utilities = true then 1 else 0 end) +
        (case when difficulty_affording_medications = true then 1 else 0 end) +
        (case when social_isolation_score >= 6 then 1 else 0 end) +
        (case when safety_concerns = true then 1 else 0 end) as total_sdoh_risk_count,

        -- Risk category
        case
            when total_sdoh_risk_count >= 4 then 'High Risk'
            when total_sdoh_risk_count >= 2 then 'Medium Risk'
            when total_sdoh_risk_count >= 1 then 'Low Risk'
            else 'No Risk'
        end as sdoh_risk_category,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed