{{
  config(
    materialized='incremental',
    unique_key='audit_id',
    incremental_strategy='append',
    tags=['marts', 'audit', 'hipaa_compliance'],
    schema = 'marts',
    cluster_by=['access_timestamp', 'hospital_id'],
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  HIPAA Audit Trail - PRODUCTION VERSION
  Tracks all access to PHI-containing tables using Snowflake Query History

  SETUP REQUIREMENTS:
  1. Grant IMPORTED PRIVILEGES on SNOWFLAKE database:
     GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE DBT_DEV_ROLE;
  2. This model runs incrementally to capture ongoing access
  3. Retention: Query history available for 365 days in ACCOUNT_USAGE
*/

with phi_tables as (
    -- Define all tables containing PHI
    select table_name, 'HIGH' as phi_level, table_schema
    from (
        values
            ('RAW_PATIENTS', 'RAW_PHI'),
            ('RAW_ENCOUNTERS', 'RAW_PHI'),
            ('RAW_BILLING_TRANSACTIONS', 'RAW_PHI'),
            ('RAW_CLINICAL_ORDERS', 'RAW_PHI'),
            ('RAW_CLINICAL_RESULTS', 'RAW_PHI'),
            ('RAW_VITAL_SIGNS', 'RAW_PHI'),
            ('RAW_MEDICATION_ADMINISTRATION', 'RAW_PHI'),
            ('RAW_PATIENT_ALLERGIES', 'RAW_PHI'),
            ('RAW_PATIENT_COVERAGE', 'RAW_PHI'),
            ('RAW_SDOH_SCREENINGS', 'RAW_PHI')
    ) as t(table_name, table_schema)

    union all

    -- Staging tables with PHI
    select table_name, 'MEDIUM' as phi_level, 'STAGING' as table_schema
    from (
        values
            ('STG_HEALTHCARE__PATIENTS'),
            ('STG_HEALTHCARE__ENCOUNTERS'),
            ('STG_HEALTHCARE__PROVIDERS')
    ) as t(table_name)
),

query_history as (
    select
        query_id,
        query_text,
        database_name,
        schema_name,
        user_name,
        role_name,
        session_id,
        warehouse_name,
        warehouse_size,
        start_time,
        end_time,
        execution_status,
        error_code,
        error_message,
        rows_produced,
        rows_inserted,
        rows_updated,
        rows_deleted,
        bytes_scanned,
        compilation_time,
        execution_time,
        total_elapsed_time,
        credits_used_cloud_services,
        query_type,
        query_tag
    from snowflake.account_usage.query_history
    where
        database_name = '{{ target.database }}'
        and execution_status = 'SUCCESS'
        {% if is_incremental() %}
        -- Only get new queries since last run
        and start_time > (select max(access_timestamp) from {{ this }})
        {% else %}
        -- Initial load: last 7 days
        and start_time >= dateadd('day', -7, current_timestamp())
        {% endif %}
),

phi_access_log as (
    select
        qh.query_id,
        qh.start_time as access_timestamp,
        qh.user_name,
        qh.role_name,
        qh.session_id,
        qh.database_name,
        qh.schema_name,
        qh.warehouse_name,
        qh.query_text,
        qh.execution_status,
        qh.rows_produced,
        qh.rows_inserted + qh.rows_updated + qh.rows_deleted as rows_modified,
        qh.bytes_scanned,
        qh.execution_time,
        qh.total_elapsed_time,

        -- Identify which PHI tables were accessed
        listagg(distinct phi.table_name, ', ') within group (order by phi.table_name) as phi_tables_accessed,
        max(phi.phi_level) as highest_phi_level,

        -- Extract hospital_id from query if present (regex pattern)
        -- Extract hospital_id from query patterns
        coalesce(
            regexp_substr(qh.query_text, 'hospital_id\\s*=\\s*[\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1),
            regexp_substr(qh.query_text, 'hospital_id\\s*IN\\s*\\([\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1),
            'UNATTRIBUTED'
        ) as hospital_id_filter,

        -- Categorize query type
        case
            when qh.query_type = 'SELECT' then 'READ'
            when qh.query_type in ('INSERT', 'UPDATE', 'DELETE', 'MERGE') then 'WRITE'
            when qh.query_type in ('CREATE', 'ALTER', 'DROP') then 'DDL'
            else 'OTHER'
        end as access_type,

        -- Access authorization assessment
        case
            when qh.role_name in ('ACCOUNTADMIN', 'SYSADMIN') then 'AUTHORIZED_ADMIN'
            when qh.role_name = 'HIPAA_AUDITOR' then 'AUTHORIZED_AUDITOR'
            when qh.role_name like 'HOSPITAL_%_PHI_ANALYST' then 'AUTHORIZED_PHI_ANALYST'
            when qh.role_name = 'DBT_DEV_ROLE' and qh.database_name like '%_DEV' then 'AUTHORIZED_DEV'
            when qh.role_name = 'DBT_PROD_ROLE' and qh.database_name like '%_PROD' then 'AUTHORIZED_PROD'
            else 'REVIEW_REQUIRED'
        end as access_authorization_status,

        -- Detect suspicious patterns
        case
            when qh.rows_produced > 10000 then true
            when (qh.rows_inserted + qh.rows_updated + qh.rows_deleted) > 1000 then true
            when qh.query_text ilike '%select * from%' and qh.rows_produced > 1000 then true
            else false
        end as is_bulk_access,

        case
            when qh.role_name not in (
                'ACCOUNTADMIN', 'SYSADMIN', 'HIPAA_AUDITOR',
                'DBT_DEV_ROLE', 'DBT_PROD_ROLE'
            )
            and qh.role_name not like 'HOSPITAL_%_PHI_ANALYST'
            and qh.role_name not like 'HOSPITAL_%_ANALYST'
            then true
            else false
        end as is_unauthorized,

        -- Calculate access duration
        datediff('second', qh.start_time, qh.end_time) as access_duration_seconds,

        -- Cost estimation
        (qh.credits_used_cloud_services * 4.0) as estimated_cost_usd

    from query_history qh
    inner join phi_tables phi
        on (
            upper(qh.query_text) like '%' || phi.table_schema || '.' || phi.table_name || '%'
            or upper(qh.query_text) like '%' || phi.table_name || '%'
        )
    group by
        qh.query_id,
        qh.start_time,
        qh.user_name,
        qh.role_name,
        qh.session_id,
        qh.database_name,
        qh.schema_name,
        qh.warehouse_name,
        qh.query_text,
        qh.execution_status,
        qh.rows_produced,
        qh.rows_inserted,
        qh.rows_updated,
        qh.rows_deleted,
        qh.bytes_scanned,
        qh.execution_time,
        qh.total_elapsed_time,
        qh.query_type,
        qh.credits_used_cloud_services,
        qh.end_time
),

enriched_audit as (
    select
        {{ dbt_utils.generate_surrogate_key(['query_id']) }} as audit_id,
        query_id,
        access_timestamp,
        user_name,
        role_name,
        session_id,
        database_name,
        schema_name,
        warehouse_name,

        -- Determine hospital_id (from filter or 'ALL' for unrestricted queries)
        coalesce(hospital_id_filter, 'ALL_HOSPITALS') as hospital_id,

        phi_tables_accessed,
        highest_phi_level as phi_level,
        access_type,
        access_authorization_status,

        -- Records accessed/modified
        rows_produced as records_accessed,
        rows_modified as records_modified,
        bytes_scanned,

        -- Flags
        is_bulk_access,
        is_unauthorized,

        -- Performance metrics
        execution_time as execution_time_ms,
        total_elapsed_time as total_elapsed_time_ms,
        access_duration_seconds,
        estimated_cost_usd,

        -- Query text (truncated for storage)
        left(query_text, 5000) as query_text_sample,

        -- Compliance notes
        case
            when is_unauthorized then 'ALERT: Unauthorized PHI access detected'
            when is_bulk_access and access_authorization_status not in ('AUTHORIZED_ADMIN', 'AUTHORIZED_AUDITOR')
                then 'WARNING: Bulk PHI access by non-admin role'
            when access_type = 'WRITE' and role_name not like 'DBT_%'
                then 'NOTICE: Direct PHI modification (non-ETL)'
            when highest_phi_level = 'HIGH' and access_authorization_status = 'REVIEW_REQUIRED'
                then 'REVIEW: High-level PHI access requires authorization review'
            else 'COMPLIANT: Standard authorized access'
        end as compliance_note,

        current_timestamp() as _dbt_loaded_at

    from phi_access_log
)

select * from enriched_audit