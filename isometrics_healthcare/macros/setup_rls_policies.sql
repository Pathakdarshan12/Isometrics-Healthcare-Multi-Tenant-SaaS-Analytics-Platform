{#
  Row access policy bodies. Kept in macros so setup_rls_policies can both
  create the policy and keep an existing one in sync (ALTER ... SET BODY),
  without CREATE OR REPLACE (which fails while the policy is attached).

  NOTE on the mapping-table subquery: inside a subquery, an unqualified
  `hospital_id` binds to the subquery table's own column, not the policy
  argument, so `m.hospital_id = hospital_id` is always true and leaks every
  tenant. The derived table renames the column so `hospital_id` can only
  resolve to the policy argument.
#}

{% macro rls_hospital_isolation_body() %}
  CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN') THEN TRUE
    WHEN CURRENT_ROLE() = 'DBT_CI_ROLE' AND CURRENT_DATABASE() = 'ISOMETRICS_CI' THEN TRUE
    WHEN CURRENT_ROLE() = 'DBT_DEV_ROLE' AND (CURRENT_DATABASE() = 'ISOMETRICS_DEV' OR CURRENT_DATABASE() LIKE '%_DEV') THEN TRUE
    WHEN CURRENT_ROLE() = 'DBT_PROD_ROLE' AND CURRENT_DATABASE() LIKE '%_PROD' THEN TRUE
    WHEN CURRENT_ROLE() = 'HIPAA_AUDITOR' THEN TRUE
    WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_ANALYST' AND CURRENT_ROLE() NOT LIKE '%_PHI_ANALYST' THEN
      hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_ANALYST', '\\1')
    WHEN CURRENT_ROLE() = 'HOSPITAL_ANALYST' THEN
      EXISTS (
        SELECT 1
        FROM (
          SELECT hospital_id AS mapped_hospital_id, user_name, access_start_date, access_end_date
          FROM {{ target.database }}.AUDIT.user_hospital_mapping
        ) m
        WHERE m.user_name = CURRENT_USER()
          AND m.mapped_hospital_id = hospital_id
          AND CURRENT_DATE() BETWEEN m.access_start_date AND m.access_end_date
      )
    ELSE FALSE
  END
{% endmacro %}

{% macro rls_phi_access_body() %}
  CASE
    WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'PHI_ADMIN', 'HIPAA_AUDITOR') THEN TRUE
    WHEN CURRENT_ROLE() = 'DBT_CI_ROLE' AND CURRENT_DATABASE() = 'ISOMETRICS_CI' THEN TRUE
    WHEN CURRENT_ROLE() = 'DBT_DEV_ROLE' AND (CURRENT_DATABASE() = 'ISOMETRICS_DEV' OR CURRENT_DATABASE() LIKE '%_DEV') THEN TRUE
    WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_PHI_ANALYST' THEN
      hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_PHI_ANALYST', '\\1')
    ELSE FALSE
  END
{% endmacro %}

{% macro setup_rls_policies() %}
  {#
    Idempotent: safe to run on every deploy in any environment.
    - never drops or replaces the user_hospital_mapping table (prod access grants live there)
    - creates policies if missing, otherwise updates their body in place
    - seeds CI test mappings only when target.name == 'ci'

      dbt run-operation setup_rls_policies
  #}
  {% set db = target.database %}

  {% set sql %}
    CREATE SCHEMA IF NOT EXISTS {{ db }}.RAW_PHI;
    CREATE SCHEMA IF NOT EXISTS {{ db }}.AUDIT;

    CREATE TABLE IF NOT EXISTS {{ db }}.AUDIT.user_hospital_mapping (
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

    CREATE ROW ACCESS POLICY IF NOT EXISTS {{ db }}.RAW_PHI.HOSPITAL_ISOLATION_POLICY
    AS (hospital_id VARCHAR) RETURNS BOOLEAN -> {{ rls_hospital_isolation_body() }}
    COMMENT = 'HIPAA-compliant hospital isolation';

    ALTER ROW ACCESS POLICY {{ db }}.RAW_PHI.HOSPITAL_ISOLATION_POLICY
    SET BODY -> {{ rls_hospital_isolation_body() }};

    CREATE ROW ACCESS POLICY IF NOT EXISTS {{ db }}.RAW_PHI.PHI_ACCESS_POLICY
    AS (hospital_id VARCHAR) RETURNS BOOLEAN -> {{ rls_phi_access_body() }}
    COMMENT = 'Restricted PHI access - requires explicit authorization';

    ALTER ROW ACCESS POLICY {{ db }}.RAW_PHI.PHI_ACCESS_POLICY
    SET BODY -> {{ rls_phi_access_body() }};

    {% if target.name == 'ci' %}
    MERGE INTO {{ db }}.AUDIT.user_hospital_mapping t
    USING (
        SELECT CURRENT_USER() AS user_name, 'DBT_CI_ROLE' AS role_name, column1 AS hospital_id
        FROM VALUES ('HOSP_0001'), ('HOSP_0002')
    ) s
    ON t.user_name = s.user_name AND t.role_name = s.role_name AND t.hospital_id = s.hospital_id
    WHEN NOT MATCHED THEN INSERT
        (user_name, role_name, hospital_id, access_start_date, access_end_date, access_reason)
        VALUES (s.user_name, s.role_name, s.hospital_id, '2024-01-01', '2099-12-31', 'CI Testing');
    {% endif %}
  {% endset %}

  {% do run_query(sql) %}
  {% do log("RLS policies created/updated in " ~ db ~ ".RAW_PHI (target: " ~ target.name ~ ")", info=True) %}

{% endmacro %}
