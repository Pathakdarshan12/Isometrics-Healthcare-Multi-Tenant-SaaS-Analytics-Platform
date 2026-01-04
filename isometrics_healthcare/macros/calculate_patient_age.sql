{% macro calculate_patient_age(date_of_birth_column, reference_date='current_date()') %}
  /*
    Calculate patient age in years from date of birth
    Handles edge cases and HIPAA compliance

    Args:
      date_of_birth_column: Column name containing DOB
      reference_date: Date to calculate age as of (default: today)

    Returns:
      Integer age in years

    Usage:
      {{ calculate_patient_age('date_of_birth') }} as age_years
  */

  datediff('year', {{ date_of_birth_column }}, {{ reference_date }})

{% endmacro %}


{% macro calculate_age_group(age_column) %}
  /*
    Categorize age into standard healthcare age groups

    Age Groups:
    - Pediatric: 0-17
    - Adult: 18-64
    - Geriatric: 65+

    Usage:
      {{ calculate_age_group('age_years') }} as age_group
  */

  case
    when {{ age_column }} < 18 then 'Pediatric'
    when {{ age_column }} between 18 and 64 then 'Adult'
    when {{ age_column }} >= 65 then 'Geriatric'
    else 'Unknown'
  end

{% endmacro %}


{% macro calculate_age_bucket(age_column) %}
  /*
    Create 10-year age buckets for demographic analysis

    Usage:
      {{ calculate_age_bucket('age_years') }} as age_bucket
  */

  case
    when {{ age_column }} < 10 then '0-9'
    when {{ age_column }} < 20 then '10-19'
    when {{ age_column }} < 30 then '20-29'
    when {{ age_column }} < 40 then '30-39'
    when {{ age_column }} < 50 then '40-49'
    when {{ age_column }} < 60 then '50-59'
    when {{ age_column }} < 70 then '60-69'
    when {{ age_column }} < 80 then '70-79'
    when {{ age_column }} < 90 then '80-89'
    when {{ age_column }} >= 90 then '90+'
    else 'Unknown'
  end

{% endmacro %}


{% macro is_pediatric(age_column) %}
  /*
    Boolean flag for pediatric patients

    Usage:
      {{ is_pediatric('age_years') }} as is_pediatric
  */

  case when {{ age_column }} < 18 then true else false end

{% endmacro %}


{% macro is_geriatric(age_column) %}
  /*
    Boolean flag for geriatric patients

    Usage:
      {{ is_geriatric('age_years') }} as is_geriatric
  */

  case when {{ age_column }} >= 65 then true else false end

{% endmacro %}