{% macro apply_rls_policy(policy_name='hospital_isolation_policy', column_name='hospital_id') %}
  {#
    Attach the tenant row access policy to the current model.

    Idempotent: checks INFORMATION_SCHEMA.POLICY_REFERENCES (real-time, unlike
    ACCOUNT_USAGE) and skips if the policy is already attached. This matters for
    incremental models, whose tables persist between runs. Uses ALTER VIEW for
    views and ALTER TABLE otherwise. Raises if a *different* row access policy
    is attached, since Snowflake allows only one per object.
  #}
  {% if execute and model.config.materialized != 'ephemeral' %}

    {% set policy_fqn = (target.database ~ '.RAW_PHI.' ~ policy_name) | upper %}
    {% set object_kind = 'view' if model.config.materialized == 'view' else 'table' %}
    {% set relation_name = this.render() %}

    {% set existing_sql %}
      select policy_db || '.' || policy_schema || '.' || policy_name as policy_fqn
      from table({{ this.database }}.information_schema.policy_references(
          ref_entity_name => '{{ relation_name }}',
          ref_entity_domain => '{{ object_kind }}'
      ))
      where policy_kind = 'ROW_ACCESS_POLICY'
    {% endset %}

    {% set existing = run_query(existing_sql).columns[0].values() %}

    {% if existing | length == 0 %}
      {% do run_query(
          'alter ' ~ object_kind ~ ' ' ~ relation_name
          ~ ' add row access policy ' ~ policy_fqn ~ ' on (' ~ column_name ~ ')'
      ) %}
      {% do log("RLS policy " ~ policy_fqn ~ " applied to " ~ relation_name, info=True) %}
    {% elif (existing[0] | upper) == policy_fqn %}
      {% do log("RLS policy already attached to " ~ relation_name ~ ", skipping", info=True) %}
    {% else %}
      {% do exceptions.raise_compiler_error(
          relation_name ~ " has unexpected row access policy " ~ existing[0]
          ~ " (expected " ~ policy_fqn ~ ")"
      ) %}
    {% endif %}

  {% endif %}
{% endmacro %}
