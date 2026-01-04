{% macro apply_rls_policy() %}
  {% set policy_name = target.database ~ '.raw_phi.hospital_isolation_policy' %}

  {% set apply_policy_sql %}
    ALTER TABLE {{ this }}
    ADD ROW ACCESS POLICY {{ policy_name }} ON (hospital_id);
  {% endset %}

  {% if execute %}
    {% do run_query(apply_policy_sql) %}
    {% do log("RLS policy: " ~ policy_name ~ " applied successfully to " ~ this, info=True) %}
  {% endif %}
{% endmacro %}