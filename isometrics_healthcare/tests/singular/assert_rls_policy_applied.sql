-- Test that RLS policy is actually applied to all mart tables

WITH mart_tables AS (
    -- Get all tables in the marts schema
    SELECT
        table_catalog,
        table_schema,
        table_name,
        CONCAT(table_catalog, '.', table_schema, '.', table_name) as full_table_name
    FROM information_schema.tables
    WHERE table_schema = 'DBT_DEV_MARTS'
      AND table_type = 'BASE TABLE'
),

active_policies AS (
    -- Get all active RLS policies and their assignments
    SELECT
        policy_name,
        policy_schema,
        policy_db as policy_database,
        ref_database_name,
        ref_schema_name,
        ref_entity_name,
        ref_entity_domain,
        policy_status,
        CONCAT(ref_database_name, '.', ref_schema_name, '.', ref_entity_name) as full_ref_name
    FROM snowflake.account_usage.policy_references
    WHERE policy_kind = 'ROW_ACCESS_POLICY'
      AND ref_entity_domain = 'TABLE'
      AND policy_status = 'ACTIVE'
),

policy_details AS (
    -- Get policy definitions to verify they reference hospital_id
    SELECT
        policy_name,
         policy_schema,
        POLICY_CATALOG as policy_database,
        policy_body,
        policy_signature
    FROM snowflake.account_usage.row_access_policies
    WHERE deleted IS NULL
)

-- Find tables WITHOUT proper RLS policies
SELECT
    mt.table_catalog as database_name,
    mt.table_schema as schema_name,
    mt.table_name,
    mt.full_table_name,
    CASE
        WHEN ap.policy_name IS NULL
        THEN 'CRITICAL: No RLS policy attached'
        WHEN ap.policy_status != 'ACTIVE'
        THEN 'CRITICAL: RLS policy exists but not ACTIVE'
        WHEN pd.policy_body IS NULL
        THEN 'ERROR: Policy reference exists but policy definition not found'
        WHEN NOT CONTAINS(LOWER(pd.policy_body), 'hospital_id')
        THEN 'WARNING: RLS policy does not reference hospital_id column'
        ELSE 'OK'
    END as rls_status,
    ap.policy_name as attached_policy,
    ap.policy_status,
    pd.policy_signature,
    -- Show snippet of policy body for verification
    LEFT(pd.policy_body, 200) as policy_body_preview
FROM mart_tables mt
LEFT JOIN active_policies ap
    ON mt.full_table_name = ap.full_ref_name
LEFT JOIN policy_details pd
    ON ap.policy_name = pd.policy_name
    AND ap.policy_schema = pd.policy_schema
    AND ap.policy_database = pd.policy_database
WHERE
    -- Only show tables with issues
    (ap.policy_name IS NULL
     OR ap.policy_status != 'ACTIVE'
     OR pd.policy_body IS NULL
     OR NOT CONTAINS(LOWER(pd.policy_body), 'hospital_id'))
ORDER BY
    CASE
        WHEN ap.policy_name IS NULL THEN 1
        WHEN ap.policy_status != 'ACTIVE' THEN 2
        WHEN pd.policy_body IS NULL THEN 3
        ELSE 4
    END,
    mt.table_name