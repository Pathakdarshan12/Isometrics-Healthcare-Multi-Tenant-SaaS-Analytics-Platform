{% macro drop_ci_schemas() %}
  {#
    Drops every schema this CI run built: the target schema itself and the
    per-layer schemas dbt derives from it (<schema>_STAGING, _MARTS,
    _TEST_FAILURES, ...). Dropping the views/tables also detaches their row
    access policies. RAW_PHI and AUDIT (policies + mapping table) are shared by
    concurrent CI runs, tiny, and recreated idempotently by setup_rls_policies,
    so they are left in place.

      dbt run-operation drop_ci_schemas        # CI only (target.name == 'ci')
  #}
  {% if target.name != 'ci' %}
    {{ exceptions.raise_compiler_error("drop_ci_schemas only runs against the 'ci' target, not '" ~ target.name ~ "'") }}
  {% endif %}

  {% set prefix = target.schema | upper %}
  {% set rows = run_query(
      "select schema_name from " ~ target.database ~ ".information_schema.schemata "
      ~ "where schema_name = '" ~ prefix ~ "' or startswith(schema_name, '" ~ prefix ~ "_')"
  ) %}
  {% for row in rows %}
    {% do run_query("drop schema if exists " ~ target.database ~ "." ~ row[0] ~ " cascade") %}
    {% do log("Dropped " ~ target.database ~ "." ~ row[0], info=True) %}
  {% endfor %}
  {% if rows | length == 0 %}
    {% do log("No schemas found for prefix " ~ prefix, info=True) %}
  {% endif %}
{% endmacro %}


{% macro report_layer_counts() %}
  {# Logs table/view counts and row totals per schema this target builds into. #}
  {% set prefix = target.schema | upper %}
  {% set rows = run_query(
      "select table_schema, table_type, count(*) as objects, sum(coalesce(row_count, 0)) as total_rows "
      ~ "from " ~ target.database ~ ".information_schema.tables "
      ~ "where startswith(table_schema, '" ~ prefix ~ "_') or table_schema = 'SNAPSHOTS' "
      ~ "group by 1, 2 order by 1, 2"
  ) %}
  {% for row in rows %}
    {% do log(row[0] ~ "  " ~ row[1] ~ ": " ~ row[2] ~ " objects, " ~ row[3] ~ " rows", info=True) %}
  {% endfor %}
{% endmacro %}
