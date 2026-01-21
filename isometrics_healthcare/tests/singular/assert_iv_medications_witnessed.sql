/*
  SAFETY TEST: IV Medications Administered Without Witness

  High-risk IV medications require double-check verification by a second nurse
  per hospital policy and best practices.

  SEVERITY: HIGH

  Expected Result: 100% witness rate for high-risk IV medications
*/

with iv_meds as (
    select
        admin_id,
        hospital_id,
        encounter_id,
        patient_id,
        medication_name,
        dose,
        route,
        administered_datetime,
        administered_by_provider_id,
        witnessed_by_provider_id,
        is_given
    from {{ ref('stg_healthcare__medication_administration') }}
    where route = 'IV'
    and is_given = true
),

violations as (
    select
        admin_id,
        hospital_id,
        encounter_id,
        patient_id,
        medication_name,
        dose,
        administered_datetime,
        administered_by_provider_id,

        -- Determine if high-risk IV med
        case
            when lower(medication_name) like any ('%insulin%', '%heparin%', '%potassium%', '%chemotherapy%')
            then true
            else false
        end as is_high_risk_iv,

        '⚠️ IV MEDICATION GIVEN WITHOUT WITNESS: ' || medication_name ||
        ' (' || dose || ') administered without second nurse verification' as error_message

    from iv_meds
    where witnessed_by_provider_id is null
    and lower(medication_name) like any ('%insulin%', '%heparin%', '%potassium%', '%chemotherapy%')
)

select
    admin_id,
    hospital_id,
    encounter_id,
    patient_id,
    medication_name,
    dose,
    administered_datetime,
    administered_by_provider_id,
    error_message,

    '⚠️ ACTION: Re-education on IV high-risk medication protocols. Document witness for future administrations.' as action_required

from violations
order by administered_datetime desc