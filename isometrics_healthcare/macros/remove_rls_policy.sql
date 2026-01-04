{% macro remove_rls_policy(model_name) %}
  /*
    Remove Row-Level Security policy from a model
    Used during development/testing
  */

  {% set target_schema = target.schema %}
  {% set target_database = target.database %}
  {% set full_table_name = target_database ~ '.' ~ target_schema ~ '.' ~ model_name %}

  {% set remove_policy_sql %}
    ALTER TABLE {{ full_table_name }}
    DROP ROW ACCESS POLICY hospital_isolation_policy;
  {% endset %}

  {% do log("Removing RLS policy from " ~ full_table_name, info=True) %}

  {% if execute %}
    {% do run_query(remove_policy_sql) %}
    {% do log("✓ RLS policy removed", info=True) %}
  {% endif %}

{% endmacro %}