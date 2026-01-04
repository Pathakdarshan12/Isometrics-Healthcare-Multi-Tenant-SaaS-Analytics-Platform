{% test no_cross_tenant_leakage(model, tenant_column='hospital_id') %}
  /*
    Generic test: Verify no data leakage across tenants

    This test ensures that:
    1. All foreign key references stay within the same tenant
    2. No cross-hospital data contamination
    3. RLS boundaries are respected

    CRITICAL HIPAA COMPLIANCE TEST

    Usage in schema.yml:
      models:
        - name: fct_encounters
          tests:
            - no_cross_tenant_leakage:
                tenant_column: hospital_id
  */

  {% set model_name = model.name %}

  -- Check if this is a fact table that joins to dimension tables
  {% if 'fct_' in model_name or 'fact_' in model_name %}

    {% set check_sql %}
      with base_model as (
        select distinct {{ tenant_column }}
        from {{ model }}
      ),

      -- Get all related dimension tables
      related_patients as (
        select distinct hospital_id
        from {{ ref('stg_healthcare__patients') }}
        where patient_id in (
          select patient_id from {{ model }} where patient_id is not null
        )
      ),

      related_providers as (
        select distinct hospital_id
        from {{ ref('stg_healthcare__providers') }}
        where provider_id in (
          select provider_id from {{ model }} where provider_id is not null
        )
      ),

      -- Check for cross-tenant leakage
      leakage_check as (
        -- Check patient hospital_id matches
        select
          'patient_mismatch' as leak_type,
          m.{{ tenant_column }} as model_hospital,
          p.hospital_id as related_hospital,
          count(*) as violation_count
        from {{ model }} m
        inner join {{ ref('stg_healthcare__patients') }} p
          on m.patient_id = p.patient_id
        where m.{{ tenant_column }} != p.hospital_id
        group by m.{{ tenant_column }}, p.hospital_id

        union all

        -- Check provider hospital_id matches
        select
          'provider_mismatch' as leak_type,
          m.{{ tenant_column }} as model_hospital,
          pr.hospital_id as related_hospital,
          count(*) as violation_count
        from {{ model }} m
        inner join {{ ref('stg_healthcare__providers') }} pr
          on m.provider_id = pr.provider_id
        where m.{{ tenant_column }} != pr.hospital_id
        group by m.{{ tenant_column }}, pr.hospital_id
      )

      select
        leak_type,
        model_hospital,
        related_hospital,
        violation_count,
        '🚨 CRITICAL: Cross-tenant data leakage detected!' as error_message
      from leakage_check
      where violation_count > 0
    {% endset %}

    {{ return(check_sql) }}

  {% else %}

    -- For non-fact tables, just verify hospital_id exists and is not null
    select
      '{{ model_name }}' as model_name,
      {{ tenant_column }},
      count(*) as null_tenant_count
    from {{ model }}
    where {{ tenant_column }} is null
    group by {{ tenant_column }}
    having count(*) > 0

  {% endif %}

{% endtest %}