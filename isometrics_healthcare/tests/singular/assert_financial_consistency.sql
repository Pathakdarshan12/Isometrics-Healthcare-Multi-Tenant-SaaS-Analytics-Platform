-- Test that length of stay is reasonable for encounter type
select
    encounter_id,
    hospital_id,
    encounter_type,
    length_of_stay,
    admission_date,
    discharge_date
from {{ ref('stg_healthcare__encounters') }}
where
    length_of_stay is not null
    and (
        -- Inpatient: 1–365 days
        (encounter_type = 'Inpatient'
         and (length_of_stay < 1 or length_of_stay > 365))

        -- Outpatient: same day only
        or (encounter_type = 'Outpatient'
            and length_of_stay >= 1)

        -- Emergency: typically < 3 days (if longer, should be admitted)
        or (encounter_type = 'Emergency'
            and length_of_stay >= 3)

        -- Observation: up to 3 days (72 hours is common limit)
        or (encounter_type = 'Observation'
            and length_of_stay > 3)

        -- Always invalid
        or length_of_stay < 0
    )