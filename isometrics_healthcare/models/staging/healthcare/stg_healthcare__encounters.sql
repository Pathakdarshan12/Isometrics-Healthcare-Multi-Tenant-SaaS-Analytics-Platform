{{
  config(
    materialized='view',
    secure = True,
    tags=['staging', 'bronze', 'encounters'],
    schema = 'staging',
    cluster_by=['hospital_id', 'encounter_id'],
    post_hook=["{{ apply_rls_policy() }}"],
    meta={
      'contains_phi': true,
      'phi_fields': ['admission_date', 'discharge_date']
    }
  )
}}

with source as (
    select *
    from {{ source('healthcare', 'raw_encounters') }}
    WHERE CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DBT_DEV_ROLE')
),

-- CRITICAL: Validate foreign key relationships have matching hospital_ids
-- This prevents cross-hospital data leakage
validated_relationships as (
    select
        s.*,

        -- Validate patient belongs to same hospital
        p.hospital_id as patient_hospital_id,

        -- Validate provider belongs to same hospital
        prov.hospital_id as provider_hospital_id,

        -- Validate facility belongs to same hospital
        f.hospital_id as facility_hospital_id,

        -- Create validation flags
        case
            when s.hospital_id != p.hospital_id then true
            else false
        end as patient_hospital_mismatch,

        case
            when s.hospital_id != prov.hospital_id then true
            else false
        end as provider_hospital_mismatch,

        case
            when s.hospital_id != f.hospital_id then true
            else false
        end as facility_hospital_mismatch

    from source s
    inner join {{ ref('stg_healthcare__patients') }} p
        on s.patient_id = p.patient_id
    inner join {{ ref('stg_healthcare__providers') }} prov
        on s.provider_id = prov.provider_id
    inner join {{ ref('stg_healthcare__facilities') }} f
        on s.facility_id = f.facility_id
),

-- Filter out any records with hospital_id mismatches (data quality issue)
clean_data as (
    select *
    from validated_relationships
    where
        patient_hospital_mismatch = false
        and provider_hospital_mismatch = false
        and facility_hospital_mismatch = false
),

-- Calculate readmissions using lag() to match test expectations
readmission_logic as (
    select
        *,
        -- Get previous encounter's discharge date for same patient
        lag(discharge_date) over (
            partition by patient_id, hospital_id
            order by admission_date
        ) as previous_discharge_date,

        -- Get previous encounter type
        lag(encounter_type) over (
            partition by patient_id, hospital_id
            order by admission_date
        ) as previous_encounter_type,

        -- Get previous encounter_id for validation
        lag(encounter_id) over (
            partition by patient_id, hospital_id
            order by admission_date
        ) as previous_encounter_id

    from clean_data
),

cleaned as (
    select
        -- Primary Key
        encounter_id,

        -- Foreign Keys
        hospital_id,  -- 🔒 CRITICAL for RLS
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

        -- Store previous encounter info for validation
        previous_encounter_id,
        previous_discharge_date,
        previous_encounter_type,

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
        -- Data quality validations
        (discharge_date is null or discharge_date >= admission_date)
        and total_charges >= 0
        and length_of_stay >= 0
        -- Ensure hospital_id is never null (CRITICAL for RLS)
        and hospital_id is not null
)

select * from validated