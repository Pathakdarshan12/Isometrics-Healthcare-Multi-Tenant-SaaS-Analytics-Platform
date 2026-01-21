{{
  config(
    materialized='table',
    tags=['marts', 'operational', 'capacity'],
    cluster_by=['hospital_id', 'metric_date'],
    schema = 'marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

with encounters as (
    select * from {{ ref('int_encounters__enriched') }}
    WHERE CURRENT_ROLE() IN ('ACCOUNTADMIN', 'DBT_DEV_ROLE') -- Admin/Dev roles see everything
),

facilities as (
    select * from {{ ref('stg_healthcare__facilities') }}
),

-- Generate date spine for occupancy calculation
date_spine as (
    select distinct
        e.hospital_id,
        d.date_day as metric_date
    from encounters e
    cross join (
        select distinct admission_date_day as date_day
        from encounters
        where admission_date_day is not null
    ) d
),

-- Calculate daily census (occupied beds)
daily_census as (
    select
        ds.hospital_id,
        ds.metric_date,
        count(distinct e.encounter_id) as occupied_beds
    from date_spine ds
    left join encounters e
        on ds.hospital_id = e.hospital_id
        and ds.metric_date >= e.admission_date_day
        and ds.metric_date < coalesce(e.discharge_date, current_date() + 1)
        and e.encounter_type = 'Inpatient'
    group by ds.hospital_id, ds.metric_date
),

daily_operational_metrics as (
    select
        e.hospital_id,
        e.admission_date_day as metric_date,

        -- Volume by Type
        count(distinct case when e.encounter_type = 'Inpatient' then e.encounter_id end) as inpatient_admissions,
        count(distinct case when e.encounter_type = 'Emergency' then e.encounter_id end) as emergency_visits,
        count(distinct case when e.encounter_type = 'Outpatient' then e.encounter_id end) as outpatient_visits,
        count(distinct case when e.encounter_type = 'Observation' then e.encounter_id end) as observation_visits,

        -- Bed Utilization (for inpatients with LOS > 0)
        sum(case when e.encounter_type = 'Inpatient' and e.length_of_stay > 0 then e.length_of_stay else 0 end) as total_patient_days,

        -- Facility Metrics
        count(distinct e.facility_id) as active_facilities,
        count(distinct case when e.facility_type = 'Emergency Department' then e.facility_id end) as ed_facilities_used,
        count(distinct case when e.facility_type = 'Intensive Care Unit' then e.facility_id end) as icu_facilities_used,

        -- Provider Metrics
        count(distinct e.provider_id) as active_providers,
        count(distinct case when e.specialty = 'Emergency Medicine' then e.provider_id end) as ed_providers,
        count(distinct case when e.specialty = 'Internal Medicine' then e.provider_id end) as medicine_providers,

        -- Patient Flow
        count(distinct case when e.admission_source = 'Emergency' then e.encounter_id end) as admits_from_ed,
        count(distinct case when e.admission_source = 'Transfer' then e.encounter_id end) as transfer_admissions,
        count(distinct case when e.admission_source = 'Elective' then e.encounter_id end) as elective_admissions,

        -- Discharge Patterns
        count(distinct case when e.discharge_disposition = 'Home' then e.encounter_id end) as discharges_to_home,
        count(distinct case when e.discharge_disposition = 'SNF' then e.encounter_id end) as discharges_to_snf,
        count(distinct case when e.discharge_disposition = 'Rehab' then e.encounter_id end) as discharges_to_rehab,

        -- Day of Week Patterns
        count(distinct case when e.admission_day_of_week = 'Monday' then e.encounter_id end) as monday_admissions,
        count(distinct case when e.admission_day_of_week = 'Friday' then e.encounter_id end) as friday_admissions,
        count(distinct case when e.admission_day_of_week in ('Saturday', 'Sunday') then e.encounter_id end) as weekend_admissions,

        -- Diagnosis Complexity
        count(distinct case when e.severity_level = 'Critical' then e.encounter_id end) as critical_cases,
        count(distinct case when e.severity_level = 'High' then e.encounter_id end) as high_severity_cases,
        count(distinct case when e.is_chronic then e.encounter_id end) as chronic_condition_encounters,

        current_timestamp() as _dbt_loaded_at

    from encounters e
    group by e.hospital_id, e.admission_date_day
),

hospital_capacity as (
    select
        f.hospital_id,
        sum(case when f.facility_type in ('Medical-Surgical Unit', 'Intensive Care Unit')
            then f.bed_capacity else 0 end) as total_bed_capacity,
        sum(case when f.facility_type = 'Intensive Care Unit'
            then f.bed_capacity else 0 end) as icu_bed_capacity,
        sum(case when f.facility_type = 'Medical-Surgical Unit'
            then f.bed_capacity else 0 end) as medsurg_bed_capacity
    from facilities f
    group by f.hospital_id
),

with_capacity as (
    select
        m.*,

        -- Bed capacity
        coalesce(hc.total_bed_capacity, 0) as total_bed_capacity,
        coalesce(hc.icu_bed_capacity, 0) as icu_bed_capacity,
        coalesce(hc.medsurg_bed_capacity, 0) as medsurg_bed_capacity,

        -- Occupied beds from census
        coalesce(dc.occupied_beds, 0) as occupied_beds,

        -- Correct bed occupancy rate (occupied beds / total capacity)
        case
            when coalesce(hc.total_bed_capacity, 0) > 0
            then (coalesce(dc.occupied_beds, 0) * 100.0) / hc.total_bed_capacity
            else 0
        end as bed_occupancy_rate_pct

    from daily_operational_metrics m
    left join hospital_capacity hc
        on m.hospital_id = hc.hospital_id
    left join daily_census dc
        on m.hospital_id = dc.hospital_id
        and m.metric_date = dc.metric_date
)

select * from with_capacity