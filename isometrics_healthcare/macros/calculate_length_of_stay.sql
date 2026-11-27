{% macro calculate_length_of_stay(admission_column, discharge_column) %}
  {#
    Length of stay in midnights (CMS convention: same-day discharge = 0 days).
    Null while the patient has not been discharged.

      {{ calculate_length_of_stay('admission_date', 'discharge_date') }} as los_midnights
  #}
  case
    when {{ discharge_column }} is null then null
    when {{ discharge_column }} < {{ admission_column }} then null
    else datediff('day', {{ admission_column }}::date, {{ discharge_column }}::date)
  end
{% endmacro %}
