-- ============================================
-- Manual RLS Testing Script
-- ============================================
-- Run this as different users to verify RLS works

-- 1. As ACCOUNTADMIN (should see ALL hospitals)
USE ROLE ACCOUNTADMIN;
SELECT
    hospital_id,
    count(*) as encounter_count
FROM {{ ref('fct_encounters') }}
GROUP BY hospital_id
ORDER BY encounter_count DESC
LIMIT 10;

-- 2. Set session to specific hospital
ALTER SESSION SET HOSPITAL_ID = 'HOSP_0001';

-- 3. As HOSPITAL_ANALYST (should see ONLY HOSP_0001)
USE ROLE HOSPITAL_ANALYST;
SELECT
    hospital_id,
    count(*) as encounter_count
FROM {{ ref('fct_encounters') }}
GROUP BY hospital_id;
-- Should return ONLY HOSP_0001

-- 4. Try to access another hospital (should return 0 rows)
SELECT *
FROM {{ ref('fct_encounters') }}
WHERE hospital_id = 'HOSP_0002'
LIMIT 10;
-- Should return 0 rows because RLS blocks it

-- 5. Switch hospital context
ALTER SESSION SET HOSPITAL_ID = 'HOSP_0002';

SELECT
    hospital_id,
    count(*) as encounter_count
FROM {{ ref('fct_encounters') }}
GROUP BY hospital_id;
-- Should now return ONLY HOSP_0002

-- 6. Verify RLS is applied to all marts
SELECT
    table_name,
    policy_name
FROM information_schema.policy_references
WHERE ref_schema_name = 'MARTS'
  AND policy_name = 'HOSPITAL_ISOLATION_POLICY'
ORDER BY table_name;