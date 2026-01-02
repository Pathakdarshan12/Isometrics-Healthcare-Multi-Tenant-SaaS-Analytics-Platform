{{
  config(
    materialized='table',
    tags=['marts', 'audit', 'hipaa_compliance']
  )
}}

/*
  HIPAA Audit Trail - SIMPLIFIED VERSION
  Tracks access to PHI-containing tables

  NOTE: This is a simplified version for demo purposes.
  In production, you would use Snowflake's ACCOUNT_USAGE.QUERY_HISTORY
  which requires special permissions.

  To enable full audit logging:
  1. Grant IMPORTED PRIVILEGES on SNOWFLAKE database to your role
  2. Use snowflake.account_usage.query_history
  3. Set up continuous audit logging
*/

with audit_placeholder as (
    -- This is a placeholder table for demo purposes
    -- In production, replace with actual query history from ACCOUNT_USAGE

    select
        {{ dbt_utils.generate_surrogate_key(['hospital_id', 'current_timestamp()']) }} as audit_id,
        hospital_id,
        current_user() as user_name,
        current_role() as role_name,
        current_timestamp() as access_timestamp,
        'DEMO_MODE' as access_authorization_status,
        'This is a demo placeholder' as note,
        0 as records_accessed,
        false as is_unauthorized,
        false as is_bulk_access

    from {{ ref('stg_healthcare__hospitals') }}
    where false  -- Returns no rows, just creates the structure
)

select
    audit_id,
    hospital_id,
    user_name,
    role_name,
    access_timestamp,
    access_authorization_status,
    note,
    records_accessed,
    is_unauthorized,
    is_bulk_access,
    current_timestamp() as _dbt_loaded_at
from audit_placeholder

/*
PRODUCTION IMPLEMENTATION:
Replace the CTE above with actual query history:

with query_log as (
    select
        query_id,
        query_text,
        user_name,
        role_name,
        session_id,
        start_time,
        end_time,
        execution_status,
        rows_produced
    from snowflake.account_usage.query_history
    where
        start_time >= dateadd('day', -1, current_date())
        and (
            lower(query_text) like '%raw_patients%'
            or lower(query_text) like '%raw_encounters%'
        )
)
...
*/