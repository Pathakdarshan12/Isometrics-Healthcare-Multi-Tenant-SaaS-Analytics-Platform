-- ============================================
-- TEST: Readmission Logic Validation
-- ============================================

/*
  Independently recomputes the 30-day readmission flag and compares it with
  stg_healthcare__encounters.is_readmission.

  The staging model uses lag() over inpatient stays; this test uses a self-join
  instead, so it does not simply restate the model's own logic.

  Definition: an inpatient admission is a readmission if the patient's most
  recent prior inpatient stay at the same hospital was discharged 1-30 days
  before this admission. Intervening ED/outpatient visits do not reset it.

  Expected Result: ZERO violations
*/

{{ config(severity='warn') }}

with encounters as (
    select
        encounter_id,
        hospital_id,
        patient_id,
        encounter_type,
        admission_date,
        discharge_date,
        is_readmission
    from {{ ref('stg_healthcare__encounters') }}
),

inpatient as (
    select * from encounters where encounter_type = 'Inpatient'
),

-- Most recent prior inpatient stay per inpatient admission
prior_stay as (
    select
        cur.encounter_id,
        prev.encounter_id as prior_encounter_id,
        prev.discharge_date as prior_discharge_date
    from inpatient cur
    join inpatient prev
        on prev.patient_id = cur.patient_id
        and prev.hospital_id = cur.hospital_id
        and (
            prev.admission_date < cur.admission_date
            or (prev.admission_date = cur.admission_date and prev.encounter_id < cur.encounter_id)
        )
    qualify row_number() over (
        partition by cur.encounter_id
        order by prev.admission_date desc, prev.encounter_id desc
    ) = 1
),

expected as (
    select
        e.encounter_id,
        e.hospital_id,
        e.patient_id,
        e.encounter_type,
        e.admission_date,
        e.is_readmission,
        p.prior_encounter_id,
        p.prior_discharge_date,
        datediff('day', p.prior_discharge_date, e.admission_date) as days_since_prior_inpatient,
        coalesce(
            e.encounter_type = 'Inpatient'
            and datediff('day', p.prior_discharge_date, e.admission_date) between 1 and 30,
            false
        ) as expected_is_readmission
    from encounters e
    left join prior_stay p on e.encounter_id = p.encounter_id
)

select
    encounter_id,
    hospital_id,
    patient_id,
    encounter_type,
    admission_date,
    is_readmission as actual_flag,
    expected_is_readmission as expected_flag,
    prior_encounter_id,
    prior_discharge_date,
    days_since_prior_inpatient,
    case
        when is_readmission and not expected_is_readmission
            then 'Flagged as readmission but no prior inpatient discharge 1-30 days earlier'
        else 'Prior inpatient discharge 1-30 days earlier but not flagged'
    end as validation_error,
    '⚠️ ACTION: Review readmission calculation logic in staging model' as action_required
from expected
where is_readmission != expected_is_readmission
