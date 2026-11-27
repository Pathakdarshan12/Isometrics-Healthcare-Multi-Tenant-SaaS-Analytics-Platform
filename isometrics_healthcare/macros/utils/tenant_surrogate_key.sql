{% macro tenant_surrogate_key(columns) %}
  {#
    Surrogate key that is always scoped to the tenant: hospital_id is prepended
    so the same natural key in two hospitals can never collide.

      {{ tenant_surrogate_key(['payer_id', 'request_month']) }} as auth_metric_key
  #}
  {{ dbt_utils.generate_surrogate_key(['hospital_id'] + columns) }}
{% endmacro %}
