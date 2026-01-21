{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'clinical', 'orders']
  )
}}

with orders as (
    select * from {{ ref('stg_healthcare__clinical_orders') }}
),

results as (
    select * from {{ ref('stg_healthcare__clinical_results') }}
),

encounters as (
    select * from {{ ref('stg_healthcare__encounters') }}
),

patients as (
    select * from {{ ref('stg_healthcare__patients') }}
),

providers as (
    select * from {{ ref('stg_healthcare__providers') }}
),

hospitals as (
    select * from {{ ref('stg_healthcare__hospitals') }}
),

procedures as (
    select * from {{ ref('stg_reference__procedures') }}
),

joined as (
    select
        -- Order identifiers
        o.order_id,
        o.hospital_id,
        o.encounter_id,
        o.patient_id,
        o.provider_id,

        -- Hospital context
        h.hospital_name,
        h.hospital_type,
        h.region,
        h.teaching_hospital,

        -- Patient demographics
        p.age_years,
        p.age_group,
        p.gender,

        -- Encounter context
        e.encounter_type,
        e.admission_date,
        e.discharge_date,
        e.length_of_stay,

        -- Ordering provider
        prov.provider_full_name as ordering_provider_name,
        prov.specialty as ordering_provider_specialty,
        prov.department as ordering_provider_department,

        -- Order details
        o.order_type,
        o.order_code,
        o.order_description,
        o.order_status,
        o.priority,
        o.performing_location,

        -- Dates
        o.order_datetime,
        o.scheduled_datetime,
        o.completed_datetime,

        -- Medication-specific
        o.medication_name,
        o.dose,
        o.route,
        o.frequency,
        o.duration_days,

        -- Lab-specific
        o.specimen_type,
        o.collection_datetime,

        -- Results linkage
        o.result_id,
        r.result_value,
        r.result_value_numeric,
        r.abnormal_flag,
        r.result_status,
        r.result_datetime,

        -- Procedure reference data
        proc.typical_charge_min,
        proc.typical_charge_max,
        proc.typical_charge_avg,

        -- Flags
        o.is_completed,
        o.is_cancelled,
        o.is_stat_order,
        r.is_abnormal,
        r.is_final as result_is_final,

        -- Calculated timing metrics
        o.completion_time_hours,
        o.scheduled_delay_hours,
        r.turnaround_time_hours as result_turnaround_hours,

        -- Time from order to result
        datediff('hour', o.order_datetime, r.result_datetime) as order_to_result_hours,

        -- Time in encounter when ordered
        datediff('day', e.admission_date, o.order_datetime) as encounter_day_of_order,

        -- Performance flags
        case
            when o.is_stat_order and o.completion_time_hours > 1 then true
            else false
        end as stat_order_delayed,

        case
            when o.order_type = 'LAB' and r.turnaround_time_hours > 24 then true
            else false
        end as lab_turnaround_delayed,

        case
            when o.order_type = 'RADIOLOGY' and o.completion_time_hours > 48 then true
            else false
        end as radiology_delayed,

        -- Metadata
        o.loaded_at_timestamp

    from orders o
    inner join hospitals h on o.hospital_id = h.hospital_id
    inner join encounters e on o.encounter_id = e.encounter_id
    inner join patients p on o.patient_id = p.patient_id
    inner join providers prov on o.provider_id = prov.provider_id
    left join results r on o.result_id = r.result_id
    left join procedures proc on o.order_code = proc.procedure_code
)

select * from joined