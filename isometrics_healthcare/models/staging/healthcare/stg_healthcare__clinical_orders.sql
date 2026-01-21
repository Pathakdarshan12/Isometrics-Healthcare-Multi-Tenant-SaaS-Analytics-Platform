{{
  config(
    materialized='view',
    tags=['staging', 'bronze', 'clinical', 'orders'],
    meta={
      'contains_phi': true,
      'phi_fields': ['order_datetime', 'scheduled_datetime', 'completed_datetime'],
      'owner': 'clinical-data-team@company.com'
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_clinical_orders') }}
),

renamed as (
    select
        -- Primary Key
        order_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        encounter_id,
        patient_id,
        provider_id,
        ordering_provider_id,
        result_id,

        -- Order Details
        order_type,
        order_code,
        order_description,
        order_status,
        priority,
        performing_location,

        -- Dates
        order_datetime,
        scheduled_datetime,
        completed_datetime,

        -- Medication-specific fields
        medication_name,
        dose,
        route,
        frequency,
        duration_days,

        -- Lab-specific fields
        specimen_type,
        collection_datetime,

        -- Flags
        case when order_status = 'COMPLETED' then true else false end as is_completed,
        case when order_status = 'CANCELLED' then true else false end as is_cancelled,
        case when priority = 'STAT' then true else false end as is_stat_order,

        -- Calculated fields
        datediff('hour', order_datetime, completed_datetime) as completion_time_hours,
        datediff('hour', order_datetime, scheduled_datetime) as scheduled_delay_hours,

        -- Metadata
        _loaded_at as loaded_at_timestamp,
        _source_file

    from source
)

select * from renamed