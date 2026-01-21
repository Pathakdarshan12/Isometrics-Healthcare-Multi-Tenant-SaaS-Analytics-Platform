{{
  config(
    materialized='table',
    tags=['marts', 'clinical_quality', 'medication_safety'],
    cluster_by=['hospital_id', 'metric_date']
  )
}}

/*
  Medication Safety Metrics - Daily Quality Dashboard
  Tracks medication administration compliance, safety violations, and adverse events
*/

with med_safety as (
    select * from {{ ref('int_clinical__medication_safety') }}
),

daily_metrics as (
    select
        hospital_id,
        date_trunc('day', administered_datetime) as metric_date,

        -- Volume metrics
        count(distinct admin_id) as total_administrations,
        count(distinct patient_id) as unique_patients_medicated,
        count(distinct medication_name) as unique_medications_used,
        count(distinct encounter_id) as encounters_with_medications,

        -- Administration status
        count(distinct case when is_given then admin_id end) as medications_given,
        count(distinct case when is_refused then admin_id end) as medications_refused,
        count(distinct case when is_held then admin_id end) as medications_held,
        count(distinct case when is_missed then admin_id end) as medications_missed,

        -- Safety compliance
        count(distinct case when is_verified then admin_id end) as verified_administrations,
        count(distinct case when is_witnessed then admin_id end) as witnessed_administrations,
        count(distinct case when is_given and barcode_scanned then admin_id end) as barcode_scanned_administrations,

        -- Timing compliance
        count(distinct case when is_late_administration then admin_id end) as late_administrations,
        avg(case when is_given then administration_delay_minutes else null end) as avg_delay_minutes,
        max(case when is_given then administration_delay_minutes else null end) as max_delay_minutes,

        -- High-risk medications
        count(distinct case when is_high_risk_medication then admin_id end) as high_risk_medication_count,
        count(distinct case when is_high_risk_medication and is_verified then admin_id end) as high_risk_verified_count,

        -- Safety violations
        count(distinct case when given_despite_allergy then admin_id end) as allergy_violations,
        count(distinct case when given_without_verification then admin_id end) as verification_violations,
        count(distinct case when iv_given_without_witness then admin_id end) as iv_witness_violations,

        -- Adverse events
        count(distinct case when has_adverse_reaction then admin_id end) as adverse_reactions,
        count(distinct case when has_adverse_reaction then patient_id end) as patients_with_adverse_reactions,

        -- Medication types
        count(distinct case when route = 'IV' then admin_id end) as iv_administrations,
        count(distinct case when route = 'PO' then admin_id end) as po_administrations,
        count(distinct case when route = 'IM' then admin_id end) as im_administrations,

        current_timestamp() as _dbt_loaded_at

    from med_safety
    where administered_datetime is not null
    group by hospital_id, date_trunc('day', administered_datetime)
),

with_rates as (
    select
        *,

        -- Compliance rates
        case
            when total_administrations > 0
            then (verified_administrations * 100.0) / total_administrations
            else 0
        end as verification_rate_pct,

        case
            when iv_administrations > 0
            then (witnessed_administrations * 100.0) / iv_administrations
            else 0
        end as iv_witness_rate_pct,

        case
            when medications_given > 0
            then (barcode_scanned_administrations * 100.0) / medications_given
            else 0
        end as barcode_scan_rate_pct,

        case
            when medications_given > 0
            then (late_administrations * 100.0) / medications_given
            else 0
        end as late_administration_rate_pct,

        -- Safety violation rates
        case
            when total_administrations > 0
            then ((allergy_violations + verification_violations + iv_witness_violations) * 100.0) / total_administrations
            else 0
        end as total_violation_rate_pct,

        case
            when medications_given > 0
            then (adverse_reactions * 100.0) / medications_given
            else 0
        end as adverse_reaction_rate_pct,

        -- Refusal/hold rates
        case
            when total_administrations > 0
            then (medications_refused * 100.0) / total_administrations
            else 0
        end as refusal_rate_pct,

        case
            when total_administrations > 0
            then (medications_held * 100.0) / total_administrations
            else 0
        end as hold_rate_pct,

        -- High-risk medication compliance
        case
            when high_risk_medication_count > 0
            then (high_risk_verified_count * 100.0) / high_risk_medication_count
            else 0
        end as high_risk_verification_rate_pct

    from daily_metrics
),

with_targets as (
    select
        *,

        -- Target compliance (industry standards)
        case when verification_rate_pct >= 95 then 'Meets Target' else 'Below Target' end as verification_compliance_status,
        case when iv_witness_rate_pct >= 98 then 'Meets Target' else 'Below Target' end as witness_compliance_status,
        case when barcode_scan_rate_pct >= 90 then 'Meets Target' else 'Below Target' end as barcode_compliance_status,
        case when late_administration_rate_pct <= 5 then 'Meets Target' else 'Above Target' end as timing_compliance_status,
        case when allergy_violations = 0 then 'No Violations' else 'Has Violations' end as allergy_safety_status,

        -- Overall safety score (0-100)
        (
            (case when verification_rate_pct >= 95 then 25 else verification_rate_pct * 0.25 end) +
            (case when iv_witness_rate_pct >= 98 then 25 else iv_witness_rate_pct * 0.25 end) +
            (case when barcode_scan_rate_pct >= 90 then 25 else barcode_scan_rate_pct * 0.25 end) +
            (case when late_administration_rate_pct <= 5 then 25
                  else greatest(0, 25 - (late_administration_rate_pct * 2)) end)
        ) as medication_safety_score

    from with_rates
)

select * from with_targets