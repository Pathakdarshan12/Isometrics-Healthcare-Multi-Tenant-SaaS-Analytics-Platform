{% macro calculate_readmission_rate(readmission_column, encounter_type_column) %}
  /*
    Calculate 30-day readmission rate per CMS methodology
    Only counts inpatient encounters
  */
  case
    when sum(case when {{ encounter_type_column }} = 'Inpatient' then 1 else 0 end) > 0
    then (
      sum(case when {{ readmission_column }} = true then 1 else 0 end) * 100.0
    ) / sum(case when {{ encounter_type_column }} = 'Inpatient' then 1 else 0 end)
    else 0
  end
{% endmacro %}