{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'clinical', 'medications', 'safety']
  )
}}

with med_admin as (
    select * from {{ ref('stg_healthcare__medication_administration') }}
),

med_orders as (
    select * from {{ ref('stg_healthcare__clinical_orders') }}
    where order_type = 'MEDICATION'
),

allergies as (
    select * from {{ ref('stg_healthcare__patient_allergies') }}
    where is_active = true
    and allergen_type = 'DRUG'
),

encounters as (
    select * from {{ ref('stg_healthcare__encounters') }}
),

patients as (
    select * from {{ ref('stg_healthcare__patients') }}
),

providers as (
    select * from {{ ref('stg_healthcare__providers') }}
),

hospitals as (
    select * from {{ ref('stg_healthcare__hospitals') }}
),

-- Check for allergy interactions
med_with_allergy_check as (
    select
        ma.admin_id,
        ma.hospital_id,
        ma.encounter_id,
        ma.patient_id,
        ma.medication_name,

        -- Check if medication matches any active allergies
        a.allergy_id,
        a.allergen_name,
        a.severity as allergy_severity,
        a.reaction_type,

        case
            when a.allergy_id is not null then true
            else false
        end as potential_allergy_conflict

    from med_admin ma
    left join allergies a
        on ma.patient_id = a.patient_id
        and ma.hospital_id = a.hospital_id
        -- Simple name matching (in production, use drug database)
        and (
            lower(ma.medication_name) like '%' || lower(a.allergen_name) || '%'
            or lower(a.allergen_name) like '%' || lower(ma.medication_name) || '%'
        )
),

enriched as (
    select
        -- Identifiers
        ma.admin_id,
        ma.hospital_id,
        ma.encounter_id,
        ma.patient_id,
        ma.order_id,

        -- Hospital context
        h.hospital_name,
        h.hospital_type,
        h.region,

        -- Patient demographics
        p.age_years,
        p.age_group,
        p.gender,

        -- Encounter context
        e.encounter_type,
        e.admission_date,
        e.length_of_stay,

        -- Administering provider
        prov.provider_full_name as administering_provider_name,
        prov.specialty as administering_provider_specialty,
        prov.provider_type as administering_provider_type,

        -- Witnessing provider
        prov_witness.provider_full_name as witnessing_provider_name,

        -- Medication details
        ma.medication_name,
        ma.dose,
        ma.route,

        -- Timing
        ma.scheduled_datetime,
        ma.administered_datetime,
        ma.administration_status,

        -- Order details
        mo.order_datetime,
        mo.frequency,
        mo.duration_days,

        -- Refusal/hold reasons
        ma.refusal_reason,
        ma.hold_reason,

        -- Verification
        ma.barcode_scanned,
        ma.is_verified,
        ma.is_witnessed,

        -- Adverse reactions
        ma.adverse_reaction_flag,
        ma.reaction_description,

        -- Allergy checking
        mac.potential_allergy_conflict,
        mac.allergen_name as conflicting_allergen,
        mac.allergy_severity as conflicting_allergy_severity,
        mac.reaction_type as expected_reaction_type,

        -- Administration flags
        ma.is_given,
        ma.is_refused,
        ma.is_held,
        ma.is_missed,
        ma.is_late_administration,
        ma.administration_delay_minutes,

        -- Safety flags
        case
            when mac.potential_allergy_conflict and ma.is_given then true
            else false
        end as given_despite_allergy,

        case
            when not ma.is_verified and ma.is_given then true
            else false
        end as given_without_verification,

        case
            when ma.is_late_administration and ma.is_given then true
            else false
        end as late_administration,

        case
            when ma.adverse_reaction_flag then true
            else false
        end as has_adverse_reaction,

        -- High-risk medication flags (simplified - should use drug database)
        case
            when lower(ma.medication_name) like any ('%warfarin%', '%heparin%', '%insulin%', '%morphine%', '%fentanyl%')
            then true
            else false
        end as is_high_risk_medication,

        -- Route-specific safety checks
        case
            when ma.route = 'IV' and not ma.is_witnessed then true
            else false
        end as iv_given_without_witness,

        -- Encounter day of administration
        datediff('day', e.admission_date, ma.administered_datetime) as encounter_day_of_admin,

        -- Time from order to administration
        datediff('hour', mo.order_datetime, ma.administered_datetime) as hours_from_order_to_admin,

        -- Metadata
        ma.loaded_at_timestamp

    from med_admin ma
    inner join hospitals h on ma.hospital_id = h.hospital_id
    inner join encounters e on ma.encounter_id = e.encounter_id
    inner join patients p on ma.patient_id = p.patient_id
    left join providers prov on ma.administered_by_provider_id = prov.provider_id
    left join providers prov_witness on ma.witnessed_by_provider_id = prov_witness.provider_id
    left join med_orders mo on ma.order_id = mo.order_id
    left join med_with_allergy_check mac
        on ma.admin_id = mac.admin_id
        and ma.hospital_id = mac.hospital_id
)

select * from enriched