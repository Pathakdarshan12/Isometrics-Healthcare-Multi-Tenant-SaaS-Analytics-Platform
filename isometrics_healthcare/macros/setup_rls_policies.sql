{% macro setup_rls_policies() %}

  {% set sql %}
    -- Create AUDIT schema
    CREATE SCHEMA IF NOT EXISTS {{ target.database }}.AUDIT;

    -- Create user_hospital_mapping table
    CREATE OR REPLACE TABLE {{ target.database }}.AUDIT.user_hospital_mapping (
        user_name VARCHAR(255),
        role_name VARCHAR(255),
        hospital_id VARCHAR(50),
        access_start_date DATE,
        access_end_date DATE,
        access_reason VARCHAR(1000),
        created_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
        created_by VARCHAR(255) DEFAULT CURRENT_USER(),
        PRIMARY KEY (user_name, role_name, hospital_id)
    ) COMMENT = 'User to hospital access mapping - HIPAA audited';

    -- Create hospital_isolation_policy
    CREATE OR REPLACE ROW ACCESS POLICY {{ target.database }}.AUDIT.hospital_isolation_policy
    AS (hospital_id VARCHAR) RETURNS BOOLEAN ->
      CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN') THEN TRUE
        WHEN CURRENT_ROLE() = 'DBT_CI_ROLE' AND CURRENT_DATABASE() = 'ISOMETRICS_CI' THEN TRUE
        WHEN CURRENT_ROLE() = 'DBT_DEV_ROLE' AND (CURRENT_DATABASE() = 'ISOMETRICS_DEV' OR CURRENT_DATABASE() LIKE '%_DEV') THEN TRUE
        WHEN CURRENT_ROLE() = 'HIPAA_AUDITOR' THEN TRUE
        WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_ANALYST' THEN
          hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_ANALYST', '\\1')
        WHEN CURRENT_ROLE() = 'HOSPITAL_ANALYST' THEN
          EXISTS (
            SELECT 1
            FROM {{ target.database }}.AUDIT.user_hospital_mapping m
            WHERE m.user_name = CURRENT_USER()
              AND m.hospital_id = hospital_id
              AND CURRENT_DATE() BETWEEN m.access_start_date AND m.access_end_date
          )
        WHEN CURRENT_ROLE() = 'DBT_PROD_ROLE' AND CURRENT_DATABASE() LIKE '%_PROD' THEN TRUE
        ELSE FALSE
      END
    COMMENT = 'HIPAA-compliant hospital isolation - CI environment';

    -- Create phi_access_policy
    CREATE OR REPLACE ROW ACCESS POLICY {{ target.database }}.AUDIT.phi_access_policy
    AS (hospital_id VARCHAR) RETURNS BOOLEAN ->
      CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'PHI_ADMIN', 'HIPAA_AUDITOR') THEN TRUE
        WHEN CURRENT_ROLE() = 'DBT_CI_ROLE' AND CURRENT_DATABASE() = 'ISOMETRICS_CI' THEN TRUE
        WHEN CURRENT_ROLE() = 'DBT_DEV_ROLE' AND (CURRENT_DATABASE() = 'ISOMETRICS_DEV' OR CURRENT_DATABASE() LIKE '%_DEV') THEN TRUE
        WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_PHI_ANALYST' THEN
          hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_PHI_ANALYST', '\\1')
        ELSE FALSE
      END
    COMMENT = 'Restricted PHI access - CI environment';

    -- Insert sample test data
    INSERT INTO {{ target.database }}.AUDIT.user_hospital_mapping
    (user_name, role_name, hospital_id, access_start_date, access_end_date, access_reason)
    VALUES
      (CURRENT_USER(), 'DBT_CI_ROLE', 'HOSP001', '2024-01-01', '2099-12-31', 'CI Testing'),
      (CURRENT_USER(), 'DBT_CI_ROLE', 'HOSP002', '2024-01-01', '2099-12-31', 'CI Testing');
  {% endset %}

  {% do run_query(sql) %}
  {% do log("RLS policies created successfully for " ~ target.database, info=True) %}

{% endmacro %}