{{
  config(
    materialized='view',
    secure = true,
    post_hook=["{{ apply_rls_policy() }}"],
    tags=['staging', 'bronze', 'clinical', 'results'],
    meta={
      'contains_phi': true,
      'phi_fields': ['result_datetime', 'collected_datetime', 'resulted_datetime']
    }
  )
}}

with source as (
    select * from {{ source('healthcare', 'raw_clinical_results') }}
),

renamed as (
    select
        -- Primary Key
        result_id,

        -- Foreign Keys
        hospital_id,      -- 🔒 CRITICAL for RLS
        order_id,
        patient_id,
        encounter_id,
        interpreting_provider_id,

        -- Test Identification
        result_type,
        test_code,
        test_name,
        component_code,
        component_name,

        -- Result Values
        result_value,
        result_value_numeric,
        result_units,
        reference_range_low,
        reference_range_high,
        abnormal_flag,

        -- Timing
        result_datetime,
        collected_datetime,
        resulted_datetime,

        -- Interpretation
        result_status,
        performing_lab,

        -- Imaging-specific
        imaging_modality,
        impression,
        report_text,

        -- Flags
        case when abnormal_flag in ('H', 'L', 'A') then true else false end as is_abnormal,
        case when abnormal_flag = 'H' then true else false end as is_high,
        case when abnormal_flag = 'L' then true else false end as is_low,
        case when result_status = 'FINAL' then true else false end as is_final,
        case when result_status = 'PRELIMINARY' then true else false end as is_preliminary,

        -- Calculated fields
        datediff('hour', collected_datetime, resulted_datetime) as turnaround_time_hours,

        -- Out of range calculation
        case
            when result_value_numeric is not null
                and reference_range_high is not null
                and result_value_numeric > reference_range_high
            then result_value_numeric - reference_range_high
            when result_value_numeric is not null
                and reference_range_low is not null
                and result_value_numeric < reference_range_low
            then reference_range_low - result_value_numeric
            else 0
        end as out_of_range_value,

        -- Metadata
        _loaded_at as loaded_at_timestamp

    from source
)

select * from renamed