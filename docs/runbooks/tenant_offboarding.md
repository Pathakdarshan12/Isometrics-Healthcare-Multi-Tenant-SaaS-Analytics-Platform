# Tenant Offboarding
## The Scenario:
Tenant "BadCorp" churns. Legal says: "Delete their data within 30 days (GDPR)"

Implementation:
sql-- macros/soft_delete_tenant.sql
{% macro soft_delete_tenant(tenant_id) %}

  -- Mark tenant as deleted in metadata
  UPDATE {{ ref('dim_tenants') }}
  SET 
    is_active = FALSE,
    deleted_at = CURRENT_TIMESTAMP(),
    deletion_reason = 'CUSTOMER_CHURN'
  WHERE tenant_id = '{{ tenant_id }}';

  -- Cascade to fact tables (soft delete via flag)
  UPDATE {{ ref('fct_orders') }}
  SET is_deleted = TRUE
  WHERE tenant_id = '{{ tenant_id }}';

{% endmacro %}
Physical Deletion (After 30 days):
sql-- analyses/hard_delete_tenant.sql
-- Run manually after retention period
DELETE FROM {{ ref('fct_orders') }}
WHERE tenant_id = '{{ tenant_id }}'
  AND deleted_at < CURRENT_DATE() - INTERVAL '30 days';
Evidence to show:

Screenshots of before/after row counts
Audit log showing deletion timestamp
Data lineage graph showing affected tables