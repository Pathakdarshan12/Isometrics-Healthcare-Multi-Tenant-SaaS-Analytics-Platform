{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'encounters']
  )
}}

with encounters as (
    select * from {{ ref('stg_healthcare__encounters') }}
),

patients as (
    select * from {{ ref('stg_healthcare__patients') }}
),

providers as (
    select * from {{ ref('stg_healthcare__providers') }}
),

facilities as (
    select * from {{ ref('stg_healthcare__facilities') }}
),

diagnoses as (
    select * from {{ ref('stg_reference__diagnoses') }}
),

hospitals as (
    select * from {{ ref('stg_healthcare__hospitals') }}
),

joined as (
    select
        -- Encounter identifiers
        e.encounter_id,
        e.hospital_id,
        e.patient_id,
        e.provider_id,
        e.facility_id,

        -- Hospital context
        h.hospital_name,
        h.hospital_type,
        h.region,
        h.teaching_hospital,

        -- Patient demographics
        p.age_years,
        p.age_group,
        p.gender,
        p.race,
        p.ethnicity,

        -- Provider details
        prov.provider_full_name,
        prov.specialty,
        prov.department,
        prov.provider_type,

        -- Facility details
        f.facility_name,
        f.facility_type,

        -- Diagnosis details
        e.primary_diagnosis_code,
        d.diagnosis_description,
        d.category as diagnosis_category,
        d.severity_level,
        d.is_chronic,

        -- Encounter details
        e.encounter_type,
        e.admission_source,
        e.discharge_disposition,
        e.admission_date,
        e.discharge_date,
        e.length_of_stay,

        -- Date dimensions
        e.admission_date_day,
        e.admission_date_month,
        e.admission_date_quarter,
        e.admission_date_year,
        e.admission_day_of_week,

        -- Financial
        e.total_charges,

        -- Quality flags
        e.is_readmission,
        e.is_mortality,
        e.is_emergency,
        e.is_transfer,

        -- Metadata
        e.loaded_at_timestamp

    from encounters e
    inner join hospitals h on e.hospital_id = h.hospital_id
    inner join patients p on e.patient_id = p.patient_id
    inner join providers prov on e.provider_id = prov.provider_id
    inner join facilities f on e.facility_id = f.facility_id
    left join diagnoses d on e.primary_diagnosis_code = d.diagnosis_code
)

select * from joined