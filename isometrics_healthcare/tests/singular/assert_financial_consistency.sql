-- Test that length of stay is reasonable for encounter type
-- Inpatient: 1-365 days
-- Outpatient/Emergency: 0 days (same day)
-- Observation: 0-2 days

select
    encounter_id,
    hospital_id,
    encounter_type,
    length_of_stay,
    admission_date,
    discharge_date
from {{ ref('stg_healthcare__encounters') }}
where
    (encounter_type = 'Inpatient' and (length_of_stay < 1 or length_of_stay > 365))
    or (encounter_type in ('Outpatient', 'Emergency') and length_of_stay > 1)
    or (encounter_type = 'Observation' and length_of_stay > 2)
    or length_of_stay < 0