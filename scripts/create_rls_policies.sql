-- ============================================
-- RLS on the raw layer + analyst / auditor roles
-- ============================================
-- Run as ACCOUNTADMIN AFTER `dbt run-operation setup_rls_policies` (and, for
-- the analyst grants, after the first `dbt run`). Idempotent: safe to rerun,
-- e.g. once more after the first production deploy to cover ISOMETRICS_PROD.
--
-- The policies themselves are NOT defined here. They live in
-- isometrics_healthcare/macros/setup_rls_policies.sql and are created (and kept
-- in sync) by dbt in <DB>.RAW_PHI as HOSPITAL_ISOLATION_POLICY and
-- PHI_ACCESS_POLICY. This script only:
--   1. attaches those policies to the raw tables (defense in depth: dbt
--      already attaches them to every staging view and mart)
--   2. creates example tenant roles and the HIPAA auditor role
--
-- ACCOUNTADMIN owns the raw tables and inherits the dbt roles (which own the
-- policies), so it holds both privileges ALTER TABLE ... ADD ROW ACCESS POLICY needs.
-- ============================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DBT_DEV_WH;

-- ============================================
-- 1. ATTACH POLICIES TO RAW TABLES
-- ============================================
-- raw_patients gets the stricter PHI policy; every other tenant-scoped table
-- gets hospital isolation. Reference tables (diagnoses, procedures, payers)
-- have no hospital_id and stay unrestricted.
-- Tables that already have a policy, and databases whose policies don't exist
-- yet, are skipped and reported instead of failing the script.
EXECUTE IMMEDIATE $$
DECLARE
  attached INTEGER DEFAULT 0;
  report VARCHAR DEFAULT '';
  stmt VARCHAR;
  targets CURSOR FOR
    SELECT d.column1 AS db, t.column1 AS tbl,
           IFF(t.column1 = 'RAW_PATIENTS', 'PHI_ACCESS_POLICY', 'HOSPITAL_ISOLATION_POLICY') AS pol
    FROM (VALUES ('ISOMETRICS_DEV'), ('ISOMETRICS_PROD')) d,
         (VALUES ('RAW_HOSPITALS'), ('RAW_PATIENTS'), ('RAW_PROVIDERS'), ('RAW_FACILITIES'),
                 ('RAW_ENCOUNTERS'), ('RAW_BILLING_TRANSACTIONS'), ('RAW_CLINICAL_ORDERS'),
                 ('RAW_CLINICAL_RESULTS'), ('RAW_VITAL_SIGNS'), ('RAW_PROBLEM_LIST'),
                 ('RAW_MEDICATION_ADMINISTRATION'), ('RAW_PATIENT_ALLERGIES'), ('RAW_CARE_PLANS'),
                 ('RAW_PATIENT_COVERAGE'), ('RAW_PRIOR_AUTHORIZATIONS'), ('RAW_SDOH_SCREENINGS'),
                 ('RAW_QUALITY_MEASURES'), ('RAW_REFERRALS')) t;
BEGIN
  FOR rec IN targets DO
    stmt := 'ALTER TABLE ' || rec.db || '.RAW_PHI.' || rec.tbl ||
            ' ADD ROW ACCESS POLICY ' || rec.db || '.RAW_PHI.' || rec.pol || ' ON (hospital_id)';
    BEGIN
      EXECUTE IMMEDIATE :stmt;
      attached := attached + 1;
    EXCEPTION
      WHEN STATEMENT_ERROR THEN
        report := report || rec.db || '.' || rec.tbl || ': ' || SQLERRM || '\n';
    END;
  END FOR;
  RETURN 'Attached ' || attached || ' policies. Skipped:\n' || report;
END;
$$;

-- Check: one row per raw table that has a policy
SELECT policy_name, ref_entity_name
FROM TABLE(ISOMETRICS_DEV.INFORMATION_SCHEMA.POLICY_REFERENCES(
    ref_entity_name => 'ISOMETRICS_DEV.RAW_PHI.RAW_ENCOUNTERS', ref_entity_domain => 'table'));

-- To detach (e.g. before dropping a table):
--   ALTER TABLE ISOMETRICS_DEV.RAW_PHI.RAW_ENCOUNTERS DROP ROW ACCESS POLICY ISOMETRICS_DEV.RAW_PHI.HOSPITAL_ISOLATION_POLICY;

-- ============================================
-- 2. TENANT ANALYST ROLES (dev examples)
-- ============================================
-- HOSPITAL_<id>_ANALYST sees only <id>'s rows (the policy parses the role name).
-- Granted to DBT_USER so the API / dashboard can switch to them in dev.
-- dbt builds dev marts into DBT_DEV_MARTS (profile schema DBT_DEV + layer).
CREATE ROLE IF NOT EXISTS HOSPITAL_HOSP_0001_ANALYST COMMENT = 'Analyst for hospital HOSP_0001';
CREATE ROLE IF NOT EXISTS HOSPITAL_HOSP_0002_ANALYST COMMENT = 'Analyst for hospital HOSP_0002';
-- Generic analyst: hospitals come from AUDIT.user_hospital_mapping
CREATE ROLE IF NOT EXISTS HOSPITAL_ANALYST COMMENT = 'Analyst; hospitals granted via AUDIT.user_hospital_mapping';

EXECUTE IMMEDIATE $$
DECLARE
  stmt VARCHAR;
  grants CURSOR FOR
    SELECT REPLACE(g.column1, '{role}', r.column1) AS sql_text
    FROM (VALUES ('HOSPITAL_HOSP_0001_ANALYST'), ('HOSPITAL_HOSP_0002_ANALYST'), ('HOSPITAL_ANALYST')) r,
         (VALUES ('GRANT USAGE ON WAREHOUSE DBT_DEV_WH TO ROLE {role}'),
                 ('GRANT USAGE ON DATABASE ISOMETRICS_DEV TO ROLE {role}'),
                 ('GRANT USAGE ON SCHEMA ISOMETRICS_DEV.DBT_DEV_MARTS TO ROLE {role}'),
                 ('GRANT SELECT ON ALL TABLES IN SCHEMA ISOMETRICS_DEV.DBT_DEV_MARTS TO ROLE {role}'),
                 ('GRANT SELECT ON FUTURE TABLES IN SCHEMA ISOMETRICS_DEV.DBT_DEV_MARTS TO ROLE {role}'),
                 ('GRANT ROLE {role} TO USER DBT_USER'),        -- API / dashboard switch to it
                 ('GRANT ROLE {role} TO ROLE ACCOUNTADMIN')) g;  -- lets you USE ROLE it below
BEGIN
  FOR rec IN grants DO
    stmt := rec.sql_text;
    EXECUTE IMMEDIATE :stmt;
  END FOR;
  RETURN 'Analyst roles granted on ISOMETRICS_DEV.DBT_DEV_MARTS';
END;
$$;

-- The policy subquery reads the mapping table as the policy owner (DBT_DEV_ROLE),
-- so HOSPITAL_ANALYST itself needs no grant on it.
MERGE INTO ISOMETRICS_DEV.AUDIT.user_hospital_mapping t
USING (
    SELECT 'DBT_USER' AS user_name, 'HOSPITAL_ANALYST' AS role_name, column1 AS hospital_id
    FROM VALUES ('HOSP_0003'), ('HOSP_0004')
) s
ON t.user_name = s.user_name AND t.role_name = s.role_name AND t.hospital_id = s.hospital_id
WHEN NOT MATCHED THEN INSERT
    (user_name, role_name, hospital_id, access_start_date, access_end_date, access_reason)
    VALUES (s.user_name, s.role_name, s.hospital_id, '2024-01-01', '2099-12-31', 'Dev example mapping');

-- ============================================
-- 3. HIPAA AUDITOR (read-only, sees every tenant)
-- ============================================
CREATE ROLE IF NOT EXISTS HIPAA_AUDITOR COMMENT = 'Regulatory auditor - read-only, all tenants';
GRANT USAGE ON WAREHOUSE DBT_DEV_WH TO ROLE HIPAA_AUDITOR;
GRANT USAGE ON DATABASE ISOMETRICS_DEV TO ROLE HIPAA_AUDITOR;
GRANT USAGE ON ALL SCHEMAS IN DATABASE ISOMETRICS_DEV TO ROLE HIPAA_AUDITOR;
GRANT SELECT ON ALL TABLES IN SCHEMA ISOMETRICS_DEV.AUDIT TO ROLE HIPAA_AUDITOR;
GRANT SELECT ON ALL TABLES IN SCHEMA ISOMETRICS_DEV.DBT_DEV_MARTS TO ROLE HIPAA_AUDITOR;
GRANT SELECT ON FUTURE TABLES IN SCHEMA ISOMETRICS_DEV.DBT_DEV_MARTS TO ROLE HIPAA_AUDITOR;

-- ============================================
-- 4. VERIFY ISOLATION
-- ============================================
-- Expect: every tenant as ACCOUNTADMIN, exactly one as the HOSP_0001 analyst,
-- HOSP_0003/HOSP_0004 as HOSPITAL_ANALYST (when run as DBT_USER; as your own
-- user the mapping has no rows, so expect zero).
USE ROLE ACCOUNTADMIN;
SELECT COUNT(DISTINCT hospital_id) AS hospitals_visible FROM ISOMETRICS_DEV.DBT_DEV_MARTS.fct_encounters;

USE ROLE HOSPITAL_HOSP_0001_ANALYST;
SELECT hospital_id, COUNT(*) AS encounters FROM ISOMETRICS_DEV.DBT_DEV_MARTS.fct_encounters GROUP BY 1;

USE ROLE ACCOUNTADMIN;
SELECT 'RLS setup complete' AS status;
