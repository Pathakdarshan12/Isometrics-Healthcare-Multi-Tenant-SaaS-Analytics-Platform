/*
  CRITICAL SAFETY TEST: High-Risk Medications Without Barcode Verification

  High-alert/high-risk medications require double verification via barcode scanning
  per Joint Commission standards and hospital policy.

  High-Risk Medication Classes (Institute for Safe Medication Practices):
  - Anticoagulants (warfarin, heparin)
  - Insulin
  - Opioids (morphine, fentanyl, hydromorphone)
  - Chemotherapy agents
  - Concentrated electrolytes

  SEVERITY: HIGH - Violations require immediate corrective action

  Expected Result: 100% verification rate for high-risk medications
*/

with med_admin as (
    select
        admin_id,
        hospital_id,
        patient_id,
        encounter_id,
        medication_name,
        dose,
        route,
        administered_datetime,
        administered_by_provider_id,
        barcode_scanned,
        is_given
    from {{ ref('stg_healthcare__medication_administration') }}
    where is_given = true
),

high_risk_without_verification as (
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
        barcode_scanned,

        -- Identify high-risk medication class
        case
            when lower(medication_name) like any ('%warfarin%', '%coumadin%') then 'Anticoagulant - Warfarin'
            when lower(medication_name) like any ('%heparin%', '%enoxaparin%', '%lovenox%') then 'Anticoagulant - Heparin'
            when lower(medication_name) like any ('%insulin%', '%novolog%', '%humalog%', '%lantus%') then 'Insulin'
            when lower(medication_name) like any ('%morphine%', '%dilaudid%', '%hydromorphone%') then 'Opioid'
            when lower(medication_name) like any ('%fentanyl%', '%oxycodone%', '%hydrocodone%') then 'Opioid'
            when lower(medication_name) like any ('%potassium chloride%', '%kcl%') and route = 'IV' then 'Concentrated Electrolyte'
            when lower(medication_name) like any ('%magnesium sulfate%') and route = 'IV' then 'Concentrated Electrolyte'
            when lower(medication_name) like any ('%chemotherapy%', '%methotrexate%', '%cisplatin%') then 'Chemotherapy'
            else 'Other High-Risk'
        end as high_risk_class,

        -- Risk level
        case
            when route = 'IV' and lower(medication_name) like any ('%potassium%', '%insulin%') then 'CRITICAL'
            when lower(medication_name) like any ('%warfarin%', '%heparin%', '%chemotherapy%') then 'HIGH'
            else 'MODERATE'
        end as risk_level,

        '🚨 HIGH-RISK MEDICATION GIVEN WITHOUT VERIFICATION: ' || medication_name ||
        ' (' || dose || ' ' || route || ') administered without barcode scan' as error_message,

        current_timestamp() as test_run_timestamp

    from med_admin
    where
        -- Identify high-risk medications
        lower(medication_name) like any (
            '%warfarin%', '%coumadin%',
            '%heparin%', '%enoxaparin%', '%lovenox%',
            '%insulin%', '%novolog%', '%humalog%', '%lantus%',
            '%morphine%', '%dilaudid%', '%hydromorphone%', '%fentanyl%',
            '%oxycodone%', '%hydrocodone%',
            '%potassium chloride%', '%kcl%',
            '%magnesium sulfate%',
            '%methotrexate%', '%cisplatin%'
        )
        -- Not verified via barcode
        and (barcode_scanned = false or barcode_scanned is null)
)

-- Return all violations
select
    admin_id,
    hospital_id,
    encounter_id,
    patient_id,
    medication_name,
    dose,
    route,
    high_risk_class,
    risk_level,
    administered_datetime,
    administered_by_provider_id,
    barcode_scanned,
    error_message,

    -- Action required
    case
        when risk_level = 'CRITICAL' then '⚠️ CRITICAL: Immediate supervisor notification and incident report required'
        when risk_level = 'HIGH' then '⚠️ HIGH: Incident report required, additional training for staff'
        else '⚠️ MODERATE: Re-education on high-risk medication protocols'
    end as action_required

from high_risk_without_verification
order by
    risk_level desc,
    administered_datetime desc