{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'quality', 'cms_measures']
  )
}}

/*
  Abstracted CMS core-measure results (raw_quality_measures) with encounter context.
  Grain: one row per measure record (measure_id).

  Targets reflect the measure specifications:
    SEP-1  antibiotics within 60 min      AMI-8a  PCI within 90 min
    STK-4  thrombolytics within 60 min    HF-2 / PN-6  process measures (no timing)
*/

with measures as (
    select * from {{ ref('stg_healthcare__quality_measures') }}
),

encounters as (
    select
        encounter_id,
        hospital_id,
        provider_id,
        facility_id,
        encounter_type,
        admission_date,
        discharge_disposition,
        is_mortality
    from {{ ref('stg_healthcare__encounters') }}
),

joined as (
    select
        m.measure_id,
        m.hospital_id,
        m.encounter_id,
        m.patient_id,
        e.provider_id,
        e.facility_id,
        e.encounter_type,
        e.admission_date,
        e.is_mortality,

        m.measure_code,
        m.measure_name,
        m.measure_category,
        m.reporting_year,
        m.reporting_quarter,

        -- Population
        m.denominator_eligible,
        m.exclusion_applied,
        m.exclusion_reason,
        m.is_measure_eligible,
        m.is_numerator_met,
        m.gap_in_care,

        -- Timing: one unified column per record, whichever the measure uses
        coalesce(
            m.door_to_antibiotic_minutes,
            m.door_to_balloon_minutes,
            m.door_to_needle_minutes
        ) as time_to_treatment_minutes,

        case m.measure_code
            when 'SEP-1' then 60
            when 'AMI-8a' then 90
            when 'STK-4' then 60
            else null
        end as target_minutes,

        m.compliance_flag
    from measures m
    inner join encounters e
        on m.encounter_id = e.encounter_id
        and m.hospital_id = e.hospital_id
)

select
    *,
    target_minutes is not null as is_timed_measure,
    case
        when target_minutes is null or time_to_treatment_minutes is null then null
        else time_to_treatment_minutes <= target_minutes
    end as met_time_target,
    -- performance counts only eligible (non-excluded) cases that met the numerator
    is_measure_eligible and coalesce(compliance_flag, false) as is_performance_met
from joined
