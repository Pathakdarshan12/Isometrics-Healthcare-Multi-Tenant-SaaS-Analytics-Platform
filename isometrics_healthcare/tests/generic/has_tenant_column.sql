{% test has_tenant_column(model) %}
  /*
    Generic test: Verify that model has hospital_id (tenant) column

    CRITICAL for multi-tenant architecture and RLS enforcement

    Usage in schema.yml:
      models:
        - name: fct_encounters
          tests:
            - has_tenant_column
  */

  {% set columns = adapter.get_columns_in_relation(model) %}
  {% set column_names = columns | map(attribute='name') | map('lower') | list %}

  {% if 'hospital_id' not in column_names %}

    -- Return error row if hospital_id column is missing
    select
      '{{ model.name }}' as model_name,
      'Missing hospital_id column - CRITICAL RLS VIOLATION' as error_message,
      '{{ column_names | join(", ") }}' as existing_columns

  {% else %}

    -- Return empty result set (test passes)
    select 1
    where 1 = 0

  {% endif %}

{% endtest %}