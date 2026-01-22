{{
  config(
    materialized='table',
    tags=['marts', 'observability', 'sla'],
    cluster_by=['hospital_id', 'check_timestamp'],
    schema = 'marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  SLA Monitoring Dashboard
  Tracks data freshness and quality per hospital

  SLA Definitions:
  - Freshness: Data must be loaded within 4 hours of source update
  - Quality: Tests must pass >99% of the time
  - Completeness: No missing required data
*/

with source_freshness as (
    -- Check when data was last loaded
    select
        'encounters' as table_name,
        hospital_id,
        max(loaded_at_timestamp) as last_load_timestamp,
        max(source_updated_at_timestamp) as last_source_update_timestamp,
        datediff('minute', last_source_update_timestamp, last_load_timestamp) as freshness_lag_minutes
    from {{ ref('stg_healthcare__encounters') }}
    group by hospital_id

    union all

    select
        'patients' as table_name,
        hospital_id,
        max(loaded_at_timestamp) as last_load_timestamp,
        null as last_source_update_timestamp,
        null as freshness_lag_minutes
    from {{ ref('stg_healthcare__patients') }}
    group by hospital_id

    union all

    select
        'billing' as table_name,
        hospital_id,
        max(loaded_at_timestamp) as last_load_timestamp,
        null as last_source_update_timestamp,
        null as freshness_lag_minutes
    from {{ ref('stg_healthcare__billing_transactions') }}
    group by hospital_id
),

data_quality_checks as (
    -- Check row counts and quality flags
    select
        hospital_id,
        count(distinct encounter_id) as total_encounters,
        count(distinct patient_id) as total_patients,
        sum(case when length_of_stay < 0 then 1 else 0 end) as invalid_los_count,
        sum(case when total_charges < 0 then 1 else 0 end) as invalid_charges_count,
        sum(case when discharge_date < admission_date then 1 else 0 end) as invalid_dates_count,

        -- Quality score
        case
            when total_encounters > 0
            then ((total_encounters - (invalid_los_count + invalid_charges_count + invalid_dates_count)) * 100.0) / total_encounters
            else 100
        end as data_quality_score_pct

    from {{ ref('fct_encounters') }}
    group by hospital_id
),

sla_summary as (
    select
        sf.hospital_id,
        current_timestamp() as check_timestamp,

        -- Freshness Metrics
        max(case when sf.table_name = 'encounters' then sf.freshness_lag_minutes end) as encounters_freshness_minutes,
        max(case when sf.table_name = 'patients' then sf.last_load_timestamp end) as patients_last_load,
        max(case when sf.table_name = 'billing' then sf.last_load_timestamp end) as billing_last_load,

        -- SLA Compliance (4 hour = 240 minute threshold)
        case
            when max(case when sf.table_name = 'encounters' then sf.freshness_lag_minutes end) <= 240
            then 'COMPLIANT'
            when max(case when sf.table_name = 'encounters' then sf.freshness_lag_minutes end) <= 360
            then 'WARNING'
            else 'BREACH'
        end as freshness_sla_status,

        -- Data Quality Metrics
        dq.total_encounters,
        dq.total_patients,
        dq.data_quality_score_pct,

        case
            when dq.data_quality_score_pct >= 99 then 'COMPLIANT'
            when dq.data_quality_score_pct >= 95 then 'WARNING'
            else 'BREACH'
        end as quality_sla_status,

        -- Error Counts
        dq.invalid_los_count,
        dq.invalid_charges_count,
        dq.invalid_dates_count,

        -- Overall SLA Status
        case
            when freshness_sla_status = 'BREACH' or quality_sla_status = 'BREACH' then 'BREACH'
            when freshness_sla_status = 'WARNING' or quality_sla_status = 'WARNING' then 'WARNING'
            else 'COMPLIANT'
        end as overall_sla_status,

        current_timestamp() as _dbt_loaded_at

    from source_freshness sf
    left join data_quality_checks dq on sf.hospital_id = dq.hospital_id
    group by sf.hospital_id, dq.total_encounters, dq.total_patients,
             dq.data_quality_score_pct, dq.invalid_los_count,
             dq.invalid_charges_count, dq.invalid_dates_count
)

select * from sla_summary