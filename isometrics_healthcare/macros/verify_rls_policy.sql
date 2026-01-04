{% macro verify_rls_policy(model_name) %}
  /*
    Verify that RLS policy is applied to a model
    Returns policy details
  */

  {% set verify_sql %}
    SELECT
      policy_name,
      ref_entity_name as table_name,
      ref_entity_domain as object_type,
      policy_status
    FROM snowflake.account_usage.policy_references
    WHERE ref_entity_name = upper('{{ model_name }}')
      AND policy_name = 'HOSPITAL_ISOLATION_POLICY'
  {% endset %}

  {% if execute %}
    {% set results = run_query(verify_sql) %}
    {% if results %}
      {% do log("✓ RLS policy verified for " ~ model_name, info=True) %}
      {{ return(results) }}
    {% else %}
      {% do log("⚠ WARNING: No RLS policy found for " ~ model_name, info=True) %}
      {{ return(none) }}
    {% endif %}
  {% endif %}

{% endmacro %}