-- Test that every tenant-scoped staging and mart model has a hospital_id column.
-- CRITICAL for RLS enforcement: the row access policy is attached ON (hospital_id).
--
-- Built from the dbt graph so it checks the schemas the current target actually
-- builds into (e.g. DBT_DEV_MARTS, DBT_PROD_MARTS) instead of a hard-coded name.
-- Reference lookups (staging/reference) have no hospital_id and are excluded.
-- Returns one row per model missing the column. Expected: zero rows.

{%- set relations = [] -%}
{%- if execute -%}
  {%- for node in graph.nodes.values()
       if node.resource_type == 'model'
       and node.fqn[1] in ['staging', 'marts']
       and node.fqn[2] != 'reference'
       and node.config.materialized in ['view', 'table', 'incremental'] -%}
    {%- do relations.append({'name': node.name, 'schema': node.schema, 'alias': node.alias}) -%}
  {%- endfor -%}
{%- endif %}

{% if relations | length == 0 %}
select null as model_name, null as table_schema, null as table_name where false
{% else %}
with expected as (
    select column1 as model_name, column2 as table_schema, column3 as table_name
    from values
    {%- for r in relations %}
        ('{{ r.name }}', '{{ r.schema | upper }}', '{{ r.alias | upper }}'){{ "," if not loop.last }}
    {%- endfor %}
)

select
    e.model_name,
    e.table_schema,
    e.table_name,
    'Missing hospital_id column' as error_message
from expected e
where not exists (
    select 1
    from {{ target.database }}.information_schema.columns c
    where c.table_schema = e.table_schema
      and c.table_name = e.table_name
      and lower(c.column_name) = 'hospital_id'
)
{% endif %}
