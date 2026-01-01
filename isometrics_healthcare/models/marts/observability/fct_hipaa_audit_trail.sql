{{
  config(
    materialized='incremental',
    unique_key='audit_id',
    incremental_strategy='append',
    tags=['marts', 'audit', 'hipaa_compliance']
  )
}}

/*
  HIPAA Audit Trail
  Tracks all access to PHI-containing tables

  Compliance Requirements:
  - Log WHO accessed data
  - Log WHAT data was accessed
  - Log WHEN access occurred
  - Log WHY (session context / query purpose)
  - Retain for 6 years (HIPAA requirement)
*/

with query_log as (
    select
        query_id,
        query_text,
        user_name,
        role_name,
        session_id,
        start_time,
        end_time,
        database_name,
        schema_name,
        execution_status,
        error_message,
        rows_produced,
        bytes_scanned
    from snowflake.account_usage.query_history
    where
        start_time >= dateadd('day', -1, current_date())
        and database_name = 'ISOMETRICS_DEV'
        -- Only log queries that access PHI tables
        and (
            lower(query_text) like '%raw_patients%'
            or lower(query_text) like '%raw_encounters%'
            or lower(query_text) like '%stg_healthcare__patients%'
            or lower(query_text) like '%stg_healthcare__encounters%'
        )

    {% if is_incremental() %}
        -- Only process new queries
        and start_time > (select max(access_timestamp) from {{ this }})
    {% endif %}
),

access_details as (
    select
        {{ dbt_utils.generate_surrogate_key(['query_id', 'start_time']) }} as audit_id,

        -- WHO
        user_name,
        role_name,

        -- Determine if role has legitimate PHI access
        case
            when role_name in ('ACCOUNTADMIN', 'SYSADMIN', 'DBT_DEV_ROLE', 'DBT_PROD_ROLE') then 'AUTHORIZED_ADMIN'
            when role_name like 'HOSPITAL_%_PHI_ANALYST' then 'AUTHORIZED_PHI_ANALYST'
            when role_name like 'HOSPITAL_%_ANALYST' then 'UNAUTHORIZED_PHI_ACCESS'
            when role_name = 'HIPAA_AUDITOR' then 'AUTHORIZED_AUDITOR'
            else 'UNKNOWN_ROLE'
        end as access_authorization_status,

        -- WHAT
        case
            when lower(query_text) like '%raw_patients%' or lower(query_text) like '%stg_healthcare__patients%'
            then 'PATIENT_DEMOGRAPHICS'
            when lower(query_text) like '%raw_encounters%' or lower(query_text) like '%stg_healthcare__encounters%'
            then 'PATIENT_ENCOUNTERS'
            else 'UNKNOWN_PHI'
        end as phi_type_accessed,

        -- Extract hospital_id from query
        regexp_substr(query_text, 'hospital_id\\s*=\\s*[\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1) as hospital_id,

        -- WHEN
        start_time as access_timestamp,

        -- HOW LONG
        datediff('second', start_time, end_time) as access_duration_seconds,

        -- RESULT
        execution_status,
        rows_produced as records_accessed,
        bytes_scanned,

        -- Red flags
        case when rows_produced > 10000 then true else false end as is_bulk_access,
        case when execution_status = 'FAIL' then true else false end as is_failed_access,
        case when access_authorization_status = 'UNAUTHORIZED_PHI_ACCESS' then true else false end as is_unauthorized,

        -- Full query (truncated for storage)
        left(query_text, 5000) as query_text_truncated,

        -- Session context
        session_id,

        current_timestamp() as _audit_logged_at

    from query_log
)

select * from access_details