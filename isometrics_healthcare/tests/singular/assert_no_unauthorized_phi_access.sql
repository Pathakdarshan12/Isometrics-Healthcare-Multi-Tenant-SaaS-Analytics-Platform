-- ============================================
-- CRITICAL HIPAA TEST: Detect Unauthorized PHI Access
-- This test should FAIL if any unauthorized access is detected
-- ============================================

select
    audit_id,
    access_timestamp,
    user_name,
    role_name,
    hospital_id,
    phi_tables_accessed,
    records_accessed,
    compliance_note,

    '🚨 UNAUTHORIZED PHI ACCESS DETECTED' as alert_message

from {{ ref('fct_hipaa_audit_trail') }}
where is_unauthorized = true
  and access_timestamp >= dateadd('day', -1, current_timestamp())

order by access_timestamp desc