{% snapshot my_snapshot %}

{{ config(
    target_schema='snapshots',
    strategy='timestamp',
    unique_key='facility_id',
    updated_at='loaded_at_timestamp',
    invalidate_hard_deletes=True
) }}

select
    facility_id,
    hospital_id,
    facility_name,
    facility_type,
    bed_capacity,
    is_active,
    opened_date,
    loaded_at_timestamp
from {{ ref('stg_healthcare__facilities') }}

{% endsnapshot %}
