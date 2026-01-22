-- ============================================
-- TEST: Cross-Hospital Data Leakage Prevention
-- LEVEL: CRITICAL
-- ============================================

/*
  This test ensures NO data leakage across hospitals by validating
  that ALL foreign key relationships have matching hospital_ids.

  SEVERITY: CRITICAL - Any violation breaks RLS security
*/

with encounters_with_fks as (
    select
        e.encounter_id,
        e.hospital_id as encounter_hospital_id,
        e.patient_id,
        e.provider_id,
        e.facility_id,

        -- Get hospital_ids from related tables
        p.hospital_id as patient_hospital_id,
        prov.hospital_id as provider_hospital_id,
        f.hospital_id as facility_hospital_id

    from {{ ref('stg_healthcare__encounters') }} e
    inner join {{ ref('stg_healthcare__patients') }} p
        on e.patient_id = p.patient_id
    inner join {{ ref('stg_healthcare__providers') }} prov
        on e.provider_id = prov.provider_id
    inner join {{ ref('stg_healthcare__facilities') }} f
        on e.facility_id = f.facility_id
),

violations as (
    select
        encounter_id,
        encounter_hospital_id,
        patient_id,
        provider_id,
        facility_id,

        -- Identify which relationships are broken
        case
            when encounter_hospital_id != patient_hospital_id
            then 'Patient from different hospital: ' || patient_hospital_id
            else null
        end as patient_violation,

        case
            when encounter_hospital_id != provider_hospital_id
            then 'Provider from different hospital: ' || provider_hospital_id
            else null
        end as provider_violation,

        case
            when encounter_hospital_id != facility_hospital_id
            then 'Facility from different hospital: ' || facility_hospital_id
            else null
        end as facility_violation,

        '🚨 CRITICAL SECURITY VIOLATION: Cross-hospital data leakage detected!' as error_message

    from encounters_with_fks
    where
        encounter_hospital_id != patient_hospital_id
        or encounter_hospital_id != provider_hospital_id
        or encounter_hospital_id != facility_hospital_id
)

select
    encounter_id,
    encounter_hospital_id,
    patient_id,
    provider_id,
    facility_id,
    patient_violation,
    provider_violation,
    facility_violation,
    error_message,

    '⚠️ IMMEDIATE ACTION: Review data load process. This violates RLS security model.' as action_required

from violations