{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'financial', 'prior_auth']
  )
}}

/*
  Prior authorizations with payer context and the financial outcome of the
  linked encounter. Grain: one row per authorization (auth_id).

  Links each authorization to its encounter's claims so denied/pending auths can
  be tied to charges at risk and to "Prior authorization not obtained" denials.
*/

with auths as (
    select * from {{ ref('stg_healthcare__prior_authorizations') }}
),

payers as (
    select payer_id, payer_name, payer_type
    from {{ ref('stg_reference__payers') }}
),

encounter_claims as (
    select
        hospital_id,
        encounter_id,
        sum(charge_amount) as encounter_charges,
        sum(payment_amount) as encounter_payments,
        boolor_agg(is_denied) as has_claim_denial,
        boolor_agg(lower(denial_reason) like '%prior authorization%') as has_prior_auth_denial
    from {{ ref('stg_healthcare__billing_transactions') }}
    group by hospital_id, encounter_id
)

select
    a.auth_id,
    a.hospital_id,
    a.patient_id,
    a.encounter_id,
    a.payer_id,
    p.payer_name,
    p.payer_type,

    a.auth_type,
    a.service_code,
    a.service_description,
    a.auth_status,
    a.is_approved,
    a.is_denied,
    a.is_pending,
    a.is_expired,
    a.expiring_soon,
    a.denial_reason,

    a.request_date,
    date_trunc('month', a.request_date) as request_month,
    a.decision_date,
    a.days_to_decision,
    case
        when a.days_to_decision is null then 'Pending'
        when a.days_to_decision <= 2 then '0-2 days'
        when a.days_to_decision <= 7 then '3-7 days'
        when a.days_to_decision <= 14 then '8-14 days'
        else '15+ days'
    end as decision_turnaround_bucket,

    a.units_authorized,
    a.units_used,
    a.units_remaining,
    a.units_utilization_pct,

    c.encounter_charges,
    c.encounter_payments,
    coalesce(c.has_claim_denial, false) as has_claim_denial,
    coalesce(c.has_prior_auth_denial, false) as has_prior_auth_denial,

    -- charges exposed when the payer has not (or not yet) approved the service
    case when a.is_denied or a.is_pending then coalesce(c.encounter_charges, 0) else 0 end
        as charges_at_risk

from auths a
left join payers p
    on a.payer_id = p.payer_id
left join encounter_claims c
    on a.encounter_id = c.encounter_id
    and a.hospital_id = c.hospital_id
