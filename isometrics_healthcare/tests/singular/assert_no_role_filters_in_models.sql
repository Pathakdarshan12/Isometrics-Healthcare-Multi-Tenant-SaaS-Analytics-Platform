-- Guard: models must not filter rows on CURRENT_ROLE().
--
-- Tenant/role access belongs in the row access policies (macros/setup_rls_policies.sql).
-- A `where current_role() in (...)` inside a model silently returns zero rows when
-- it is built or queried under another role (CI, prod, analysts), and every
-- downstream model inherits the empty result.
--
-- Checks each model's SQL (comments stripped) at compile time. Expected: zero rows.

{%- set offenders = [] -%}
{%- if execute -%}
  {%- for node in graph.nodes.values() if node.resource_type == 'model' -%}
    {%- set code = modules.re.sub('/\\*.*?\\*/|--[^\\n]*', '', node.raw_code, flags=modules.re.S) | lower -%}
    {%- if 'current_role()' in code -%}
      {%- do offenders.append(node.original_file_path | replace('\\', '/')) -%}
    {%- endif -%}
  {%- endfor -%}
{%- endif %}

{% if offenders | length == 0 %}
select null as model_path where false
{% else %}
  {% for path in offenders %}
select '{{ path }}' as model_path, 'Model filters on CURRENT_ROLE(); use the row access policy instead' as issue
    {% if not loop.last %}union all{% endif %}
  {% endfor %}
{% endif %}
