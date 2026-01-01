{% snapshot snap_hospitals %}

{{
    config(
      target_schema='snapshots',
      unique_key='hospital_id',
      strategy='check',
      check_cols=['contract_tier', 'bed_count', 'is_active'],
      invalidate_hard_deletes=True
    )
}}

select
    hospital_id,
    hospital_name,
    hospital_type,
    bed_count,
    city,
    state,
    region,
    emr_system,
    contract_tier,
    contract_start_date,
    is_active,
    teaching_hospital,
    loaded_at_timestamp
from {{ ref('stg_healthcare__hospitals') }}

{% endsnapshot %}