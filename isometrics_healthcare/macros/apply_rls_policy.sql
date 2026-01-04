{% macro apply_rls_policy(model_name) %}
  /*
    Apply Row-Level Security policy to a model
    Ensures hospital_id-based tenant isolation

    Usage:
      {{ apply_rls_policy('fct_encounters') }}
  */

  {% set target_schema = target.schema %}
  {% set target_database = target.database %}
  {% set full_table_name = target_database ~ '.' ~ target_schema ~ '.' ~ model_name %}

  {% set apply_policy_sql %}
    ALTER TABLE {{ full_table_name }}
    ADD ROW ACCESS POLICY hospital_isolation_policy ON (hospital_id);
  {% endset %}

  {% do log("Applying RLS policy to " ~ full_table_name, info=True) %}

  {% if execute %}
    {% do run_query(apply_policy_sql) %}
    {% do log("✓ RLS policy applied successfully", info=True) %}
  {% endif %}

{% endmacro %}