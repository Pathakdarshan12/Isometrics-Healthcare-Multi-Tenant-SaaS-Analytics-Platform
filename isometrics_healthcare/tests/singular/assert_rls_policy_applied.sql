-- Test that the tenant RLS policy is attached to every tenant-scoped staging and
-- mart model (reference lookups have no hospital_id and are excluded).
--
-- Uses INFORMATION_SCHEMA.POLICY_REFERENCES (real-time) per model, built from
-- the dbt graph, so it works in any target (dev / ci / prod) without hard-coded
-- schema names and without ACCOUNT_USAGE latency (up to 2 hours).
-- Returns one row per model missing the policy. Expected: zero rows.

{% set checks = [] %}
{% if execute %}
  {% for node in graph.nodes.values()
       if node.resource_type == 'model'
       and node.fqn[1] in ['staging', 'marts']
       and node.fqn[2] != 'reference'
       and node.config.materialized in ['view', 'table', 'incremental'] %}
    {% do checks.append({
        'name': node.name,
        'relation': node.relation_name,
        'domain': 'view' if node.config.materialized == 'view' else 'table'
    }) %}
  {% endfor %}
{% endif %}

{% if checks | length == 0 %}
select null as model_name, null as relation_name, null as rls_status where false
{% else %}
with policy_checks as (
  {% for c in checks %}
    select
        '{{ c.name }}' as model_name,
        '{{ c.relation }}' as relation_name,
        count_if(
            policy_kind = 'ROW_ACCESS_POLICY'
            and upper(policy_name) = 'HOSPITAL_ISOLATION_POLICY'
            and contains(upper(ref_arg_column_names), 'HOSPITAL_ID')
        ) as rls_policy_count
    from table({{ target.database }}.information_schema.policy_references(
        ref_entity_name => '{{ c.relation }}',
        ref_entity_domain => '{{ c.domain }}'
    ))
    {% if not loop.last %}union all{% endif %}
  {% endfor %}
)

select
    model_name,
    relation_name,
    'CRITICAL: hospital_isolation_policy not attached on hospital_id' as rls_status
from policy_checks
where rls_policy_count = 0
{% endif %}
