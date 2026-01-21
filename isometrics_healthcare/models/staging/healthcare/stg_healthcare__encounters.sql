with source as (
    select *
    from {{ source('healthcare', 'raw_encounters') }}
    WHERE CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DBT_DEV_ROLE')
),

-- Add this new CTE to calculate readmissions
readmission_logic as (
    select
        *,
        -- Get previous encounter's discharge date for same patient
        lag(discharge_date) over (
            partition by patient_id
            order by admission_date
        ) as previous_discharge_date,

        -- Get previous encounter type
        lag(encounter_type) over (
            partition by patient_id
            order by admission_date
        ) as previous_encounter_type
    from source
),

cleaned as (
    select
        -- Primary Key
        encounter_id,

        -- Foreign Keys
        hospital_id,
        patient_id,
        provider_id,
        facility_id,
        primary_diagnosis_code,

        -- Encounter Details
        encounter_type,
        admission_source,
        discharge_disposition,

        -- Dates
        admission_date,
        discharge_date,
        length_of_stay,

        -- Derived date parts
        date_trunc('day', admission_date) as admission_date_day,
        date_trunc('month', admission_date) as admission_date_month,
        date_trunc('year', admission_date) as admission_date_year,
        date_trunc('quarter', admission_date) as admission_date_quarter,

        dayname(admission_date) as admission_day_of_week,
        dayofweek(admission_date) as admission_day_of_week_num,

        -- Financial
        total_charges,

        -- Quality Indicators - NOW ACTUALLY CALCULATED
        case
            when encounter_type = 'Inpatient'  -- Current encounter is inpatient
                and previous_encounter_type = 'Inpatient'  -- Previous was also inpatient
                and previous_discharge_date is not null
                and datediff('day', previous_discharge_date, admission_date) between 1 and 30
            then true
            else false
        end as is_readmission,

        -- Store days since last discharge for analysis
        case
            when previous_discharge_date is not null
            then datediff('day', previous_discharge_date, admission_date)
            else null
        end as days_since_last_discharge,

        -- Flags
        case
            when discharge_disposition = 'Deceased' then true
            else false
        end as is_mortality,

        case
            when encounter_type = 'Emergency' then true
            else false
        end as is_emergency,

        case
            when admission_source = 'Transfer' then true
            else false
        end as is_transfer,

        -- Metadata
        _loaded_at as loaded_at_timestamp,
        _source_updated_at as source_updated_at_timestamp

    from readmission_logic
),

validated as (
    select *
    from cleaned
    where
        (discharge_date is null or discharge_date >= admission_date)
        and total_charges >= 0
        and length_of_stay >= 0
)

select * from validated