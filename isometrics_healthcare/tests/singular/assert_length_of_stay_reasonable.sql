-- Test that length of stay is reasonable for encounter type
-- Inpatient: typically 1-365 days (but can be 0 for same-day admits/discharges)
-- Outpatient: typically 0 days (same day)
-- Emergency: 0-1 days (same day or brief observation)
-- Observation: 0-3 days
select
    encounter_id,
    hospital_id,
    encounter_type,
    length_of_stay,
    admission_date,
    discharge_date,
    case
        when encounter_type = 'Inpatient' and length_of_stay > 365
            then 'Inpatient LOS > 365 days'
        when encounter_type = 'Inpatient' and length_of_stay = 0 and discharge_date is not null
            then 'Inpatient same-day discharge (unusual)'
        when encounter_type = 'Outpatient' and length_of_stay > 1
            then 'Outpatient LOS > 1 day'
        when encounter_type = 'Emergency' and length_of_stay > 2
            then 'Emergency LOS > 2 days (should be admitted)'
        when encounter_type = 'Observation' and length_of_stay > 3
            then 'Observation LOS > 3 days'
        when length_of_stay < 0
            then 'Negative LOS (data error)'
    end as issue_type
from {{ ref('stg_healthcare__encounters') }}
where
    (encounter_type = 'Inpatient' and length_of_stay > 365)
    or (encounter_type = 'Inpatient' and length_of_stay = 0 and discharge_date is not null)
    or (encounter_type = 'Outpatient' and length_of_stay > 1)
    or (encounter_type = 'Emergency' and length_of_stay > 2)
    or (encounter_type = 'Observation' and length_of_stay > 3)
    or length_of_stay < 0