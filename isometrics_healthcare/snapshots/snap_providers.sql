{% snapshot snap_providers %}

{{
    config(
      target_schema='snapshots',
      unique_key='provider_id',
      strategy='timestamp',
      updated_at='loaded_at_timestamp',
      invalidate_hard_deletes=True
    )
}}

select
    provider_id,
    hospital_id,
    npi,
    provider_first_name,
    provider_last_name,
    provider_full_name,
    specialty,
    department,
    provider_type,
    is_active,
    accepts_new_patients,
    hire_date,
    years_of_service,
    loaded_at_timestamp
from {{ ref('stg_healthcare__providers') }}

{% endsnapshot %}