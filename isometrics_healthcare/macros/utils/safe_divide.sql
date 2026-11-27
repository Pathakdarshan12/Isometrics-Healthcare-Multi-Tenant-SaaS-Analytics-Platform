{% macro safe_divide(numerator, denominator, default='null') %}
  {#
    Division that returns `default` (null by default) instead of erroring or
    returning a misleading 0 when the denominator is 0 or null.

      {{ safe_divide('sum(paid_amount)', 'sum(charge_amount)') }}
  #}
  case
    when {{ denominator }} is null or {{ denominator }} = 0 then {{ default }}
    else ({{ numerator }}) / ({{ denominator }})
  end
{% endmacro %}


{% macro calculate_percentage(numerator, denominator, decimals=2) %}
  {#
    Percentage (0-100) rounded to `decimals`; null when the denominator is 0/null.

      {{ calculate_percentage('count_if(is_compliant)', 'count(*)') }} as compliance_rate_pct
  #}
  round({{ safe_divide('(' ~ numerator ~ ') * 100.0', denominator) }}, {{ decimals }})
{% endmacro %}
