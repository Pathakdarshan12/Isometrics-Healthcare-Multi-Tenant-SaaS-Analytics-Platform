{% macro remove_rls_policy(model_name, object_kind='table', policy_name='hospital_isolation_policy') %}
  {#
    Remove the tenant row access policy from a model (dev/testing only).
    object_kind: 'table' (tables, incremental models) or 'view' (staging models).

      dbt run-operation remove_rls_policy --args '{model_name: stg_healthcare__patients, object_kind: view}'
  #}

  {% set node = graph.nodes.values() | selectattr('name', 'equalto', model_name) | first %}
  {% if node is none %}
    {% do exceptions.raise_compiler_error("Model not found: " ~ model_name) %}
  {% endif %}

  {% set remove_policy_sql %}
    alter {{ object_kind }} {{ node.relation_name }}
    drop row access policy {{ target.database }}.raw_phi.{{ policy_name }}
  {% endset %}

  {% if execute %}
    {% do log("Removing RLS policy from " ~ node.relation_name, info=True) %}
    {% do run_query(remove_policy_sql) %}
    {% do log("RLS policy removed", info=True) %}
  {% endif %}

{% endmacro %}
