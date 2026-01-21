/*
  CRITICAL SAFETY TEST: Medications Given Despite Known Allergies

  This test identifies cases where medications were administered to patients
  who have documented allergies to those medications or drug classes.

  SEVERITY: CRITICAL - Any violations require immediate review

  Expected Result: ZERO violations
*/

with med_admin as (
    select
        admin_id,
        hospital_id,
        patient_id,
        encounter_id,
        medication_name,
        administered_datetime,
        is_given,
        administered_by_provider_id,
        barcode_scanned
    from {{ ref('stg_healthcare__medication_administration') }}
    where is_given = true  -- Only check medications that were actually given
),

active_allergies as (
    select
        patient_id,
        hospital_id,
        allergen_name,
        allergen_type,
        severity,
        reaction_type,
        allergy_id
    from {{ ref('stg_healthcare__patient_allergies') }}
    where is_active = true
    and allergen_type = 'DRUG'
),

-- Check for direct medication name matches
allergy_violations as (
    select
        ma.admin_id,
        ma.hospital_id,
        ma.encounter_id,
        ma.patient_id,
        ma.medication_name as administered_medication,
        ma.administered_datetime,
        ma.administered_by_provider_id,
        aa.allergen_name as known_allergy,
        aa.severity as allergy_severity,
        aa.reaction_type as expected_reaction,
        aa.allergy_id,

        -- Match type
        case
            when lower(ma.medication_name) = lower(aa.allergen_name) then 'Exact Match'
            when lower(ma.medication_name) like '%' || lower(aa.allergen_name) || '%' then 'Partial Match (Med contains Allergen)'
            when lower(aa.allergen_name) like '%' || lower(ma.medication_name) || '%' then 'Partial Match (Allergen contains Med)'
            else 'No Match'
        end as match_type,

        -- Verification status
        ma.barcode_scanned,

        -- Critical flag
        case
            when aa.severity in ('SEVERE', 'LIFE_THREATENING') then true
            else false
        end as is_critical_severity,

        -- Error message
        '🚨 CRITICAL SAFETY VIOLATION: Patient received ' || ma.medication_name ||
        ' despite documented allergy to ' || aa.allergen_name ||
        ' (Severity: ' || aa.severity || ')' as error_message,

        current_timestamp() as test_run_timestamp

    from med_admin ma
    inner join active_allergies aa
        on ma.patient_id = aa.patient_id
        and ma.hospital_id = aa.hospital_id
    where
        -- Direct name match
        lower(ma.medication_name) like '%' || lower(aa.allergen_name) || '%'
        or lower(aa.allergen_name) like '%' || lower(ma.medication_name) || '%'
)

-- Return all violations (should be ZERO)
select
    admin_id,
    hospital_id,
    encounter_id,
    patient_id,
    administered_medication,
    known_allergy,
    allergy_severity,
    expected_reaction,
    match_type,
    administered_datetime,
    administered_by_provider_id,
    barcode_scanned,
    is_critical_severity,
    error_message,

    -- Additional context for investigation
    '⚠️ IMMEDIATE ACTION REQUIRED: Review patient chart, verify administration, assess for adverse reaction' as action_required

from allergy_violations
order by
    is_critical_severity desc,  -- Critical allergies first
    administered_datetime desc