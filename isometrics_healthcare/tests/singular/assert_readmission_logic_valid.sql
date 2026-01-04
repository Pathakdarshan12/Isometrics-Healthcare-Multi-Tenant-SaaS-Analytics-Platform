-- Test that readmission logic is correctly implemented
-- A readmission must meet ALL criteria:
-- 1. Patient was previously discharged (has prior encounter)
-- 2. New admission is within 30 days of previous discharge
-- 3. Previous encounter was also an inpatient admission
-- 4. Same patient, same hospital

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
    where encounter_type = 'Inpatient'
),

-- For each encounter marked as readmission, verify there's a valid prior encounter
readmission_validation as (
    select
        curr.encounter_id as current_encounter_id,
        curr.hospital_id,
        curr.patient_id,
        curr.admission_date as current_admission,
        curr.is_readmission,

        -- Look for previous encounter
        prev.encounter_id as previous_encounter_id,
        prev.discharge_date as previous_discharge,

        -- Calculate days between
        datediff('day', prev.discharge_date, curr.admission_date) as days_since_discharge,

        -- Validation flags
        case when prev.encounter_id is null then false else true end as has_previous_encounter,
        case when days_since_discharge between 1 and 30 then true else false end as within_30_days,
        case when prev.encounter_type = 'Inpatient' then true else false end as previous_was_inpatient

    from encounters curr
    left join encounters prev
        on curr.patient_id = prev.patient_id
        and curr.hospital_id = prev.hospital_id
        and prev.discharge_date < curr.admission_date
        and prev.encounter_id != curr.encounter_id
        -- Get the most recent prior encounter
        and prev.discharge_date = (
            select max(discharge_date)
            from encounters e2
            where e2.patient_id = curr.patient_id
              and e2.hospital_id = curr.hospital_id
              and e2.discharge_date < curr.admission_date
        )
    where curr.is_readmission = true
)

-- Return violations where readmission flag doesn't match logic
select
    current_encounter_id,
    hospital_id,
    patient_id,
    current_admission,
    previous_discharge,
    days_since_discharge,
    is_readmission,
    has_previous_encounter,
    within_30_days,
    previous_was_inpatient,

    case
        when not has_previous_encounter then 'Marked as readmission but no previous encounter found'
        when not within_30_days then 'Marked as readmission but outside 30-day window (days: ' || days_since_discharge || ')'
        when not previous_was_inpatient then 'Marked as readmission but previous encounter was not inpatient'
        else 'Unknown validation error'
    end as validation_error

from readmission_validation
where
    -- Encounter is marked as readmission but doesn't meet criteria
    is_readmission = true
    and (
        not has_previous_encounter
        or not within_30_days
        or not previous_was_inpatient
    )