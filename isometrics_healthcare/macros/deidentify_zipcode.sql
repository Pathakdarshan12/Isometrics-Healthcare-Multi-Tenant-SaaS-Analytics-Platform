{% macro deidentify_zipcode(zipcode_column) %}
  /*
    HIPAA Safe Harbor de-identification for ZIP codes (45 CFR 164.514(b)(2)(i)(B)):
    keep only the first 3 digits, except for 3-digit ZIP areas with a population
    of 20,000 or fewer, which must be replaced with '000'. The restricted list
    below is the HHS-published set based on 2000 Census data.
  */
  case
    when {{ zipcode_column }} is null then null
    when not regexp_like(left(trim({{ zipcode_column }}::varchar), 3), '[0-9]{3}') then '000'
    when left(trim({{ zipcode_column }}::varchar), 3) in (
        '036', '059', '063', '102', '203', '556', '692', '790', '821',
        '823', '830', '831', '878', '879', '884', '890', '893'
    ) then '000'
    else left(trim({{ zipcode_column }}::varchar), 3)
  end
{% endmacro %}
