{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'clinical', 'allergies'],
    meta={
      'contains_phi': true,
      'phi_fields': ['onset_date', 'resolution_date']
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_patient_allergies') }}
),

renamed as (
    select
        -- Primary Key
        allergy_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        patient_id,
        documented_by_provider_id,

        -- Allergen details
        allergen_type,
        allergen_code,
        allergen_name,

        -- Reaction details
        reaction_type,
        severity,

        -- Status
        allergy_status,
        onset_date,
        resolution_date,

        -- Documentation
        documentation_date,
        clinical_notes,

        -- Flags
        case when allergy_status = 'ACTIVE' then true else false end as is_active,
        case when severity = 'LIFE_THREATENING' then true else false end as is_life_threatening,
        case when severity in ('SEVERE', 'LIFE_THREATENING') then true else false end as is_severe,
        case when allergen_type = 'DRUG' then true else false end as is_drug_allergy,
        case when allergen_type = 'FOOD' then true else false end as is_food_allergy,
        case when reaction_type = 'ANAPHYLAXIS' then true else false end as is_anaphylaxis,

        -- Duration calculation
        case
            when allergy_status = 'RESOLVED' and resolution_date is not null
            then datediff('day', onset_date, resolution_date)
            when allergy_status = 'ACTIVE'
            then datediff('day', onset_date, current_date())
            else null
        end as allergy_duration_days,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed