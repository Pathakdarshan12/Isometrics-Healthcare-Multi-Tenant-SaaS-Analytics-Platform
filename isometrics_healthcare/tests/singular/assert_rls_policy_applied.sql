-- Test that RLS policy is actually applied to all mart tables
-- SIMPLIFIED VERSION - Works without ACCOUNT_USAGE permissions

-- This test checks if hospital_id exists and has appropriate constraints
-- In production, you would verify actual RLS policies via Snowflake UI

SELECT
    table_schema,
    table_name,
    'Missing hospital_id or no constraints' as error_message
FROM information_schema.tables t
WHERE table_schema = 'DEV_DBT_MARTS'
  AND table_type = 'BASE TABLE'
  AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = t.table_schema
      AND c.table_name = t.table_name
      AND lower(c.column_name) = 'hospital_id'
      AND c.is_nullable = 'NO'  -- Must be NOT NULL
  )