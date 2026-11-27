-- ============================================
-- Seed ISOMETRICS_PROD.RAW_PHI from ISOMETRICS_DEV.RAW_PHI (one time)
-- ============================================
-- The scheduled pipeline only appends new 3-hour batches; it needs the master
-- data (hospitals, patients, providers, facilities, payers, ...) and some
-- history already in prod. Run as ACCOUNTADMIN after load_data_to_snowflake.sql
-- has loaded dev.
--
-- Safe to rerun: a prod table that already has rows is left untouched, so this
-- never overwrites batches the pipeline has loaded.
-- ============================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DBT_PROD_WH;

EXECUTE IMMEDIATE $$
DECLARE
  n INTEGER;
  src VARCHAR;
  tgt VARCHAR;
  report VARCHAR DEFAULT '';
  tables CURSOR FOR
    SELECT column1 AS tbl FROM VALUES
      ('RAW_HOSPITALS'), ('RAW_PATIENTS'), ('RAW_PROVIDERS'), ('RAW_FACILITIES'),
      ('RAW_DIAGNOSES'), ('RAW_PROCEDURES'), ('RAW_PAYERS'), ('RAW_ENCOUNTERS'),
      ('RAW_BILLING_TRANSACTIONS'), ('RAW_CLINICAL_ORDERS'), ('RAW_CLINICAL_RESULTS'),
      ('RAW_VITAL_SIGNS'), ('RAW_PROBLEM_LIST'), ('RAW_MEDICATION_ADMINISTRATION'),
      ('RAW_PATIENT_ALLERGIES'), ('RAW_CARE_PLANS'), ('RAW_PATIENT_COVERAGE'),
      ('RAW_PRIOR_AUTHORIZATIONS'), ('RAW_SDOH_SCREENINGS'), ('RAW_QUALITY_MEASURES'),
      ('RAW_REFERRALS');
BEGIN
  FOR rec IN tables DO
    src := 'ISOMETRICS_DEV.RAW_PHI.' || rec.tbl;
    tgt := 'ISOMETRICS_PROD.RAW_PHI.' || rec.tbl;
    SELECT COUNT(*) INTO :n FROM IDENTIFIER(:tgt);
    IF (n = 0) THEN
      -- prod tables were created LIKE the dev ones, so column order matches
      INSERT INTO IDENTIFIER(:tgt) SELECT * FROM IDENTIFIER(:src);
      report := report || rec.tbl || ': copied\n';
    ELSE
      report := report || rec.tbl || ': already has ' || n || ' rows, skipped\n';
    END IF;
  END FOR;
  RETURN report;
END;
$$;

SELECT 'hospitals' AS t, COUNT(*) AS n FROM ISOMETRICS_PROD.RAW_PHI.raw_hospitals
UNION ALL SELECT 'patients',   COUNT(*) FROM ISOMETRICS_PROD.RAW_PHI.raw_patients
UNION ALL SELECT 'encounters', COUNT(*) FROM ISOMETRICS_PROD.RAW_PHI.raw_encounters;
