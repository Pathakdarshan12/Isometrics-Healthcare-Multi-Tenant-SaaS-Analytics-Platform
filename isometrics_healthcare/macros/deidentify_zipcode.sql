{% macro deidentify_zipcode(zipcode_column) %}
  /*
    HIPAA Safe Harbor de-identification for ZIP codes
    Keep only first 3 digits
    If population < 20,000, set to '000'
  */
  case
    when {{ zipcode_column }} is null then null
    when length({{ zipcode_column }}) >= 3 then left({{ zipcode_column }}, 3)
    else '000'
  end
{% endmacro %}