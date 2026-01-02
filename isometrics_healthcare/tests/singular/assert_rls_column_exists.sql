-- Test that ALL mart tables have hospital_id column
-- CRITICAL for RLS enforcement

SELECT
    table_schema,
    table_name,
    'Missing hospital_id column' as error_message
FROM information_schema.tables t
WHERE table_schema = 'MARTS'
  AND table_type = 'BASE TABLE'
  AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns c
    WHERE c.table_schema = t.table_schema
      AND c.table_name = t.table_name
      AND lower(c.column_name) = 'hospital_id'
  )