{{
  config(
    materialized='table',
    tags=['marts', 'financial', 'prior_auth', 'daily'],
    cluster_by=['hospital_id', 'request_month'],
    schema='marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  Prior authorization performance by payer.
  Grain: hospital_id x payer_id x request_month

  Approval / denial rates use decided authorizations (approved + denied + expired)
  as the denominator so pending requests don't dilute the rates.
*/

with auths as (
    select * from {{ ref('int_financial__prior_authorizations_enriched') }}
),

aggregated as (
    select
        hospital_id,
        payer_id,
        any_value(payer_name) as payer_name,
        any_value(payer_type) as payer_type,
        request_month,

        count(*) as auth_requests,
        count_if(is_approved) as auths_approved,
        count_if(is_denied) as auths_denied,
        count_if(is_pending) as auths_pending,
        count_if(auth_status = 'EXPIRED' or is_expired) as auths_expired,
        count_if(expiring_soon and not is_expired) as auths_expiring_within_30_days,

        {{ calculate_percentage('count_if(is_approved)', 'count_if(not is_pending)') }} as approval_rate_pct,
        {{ calculate_percentage('count_if(is_denied)', 'count_if(not is_pending)') }} as denial_rate_pct,

        round(avg(days_to_decision), 1) as avg_days_to_decision,
        round(median(days_to_decision), 1) as median_days_to_decision,
        count_if(days_to_decision > 14) as decisions_over_14_days,

        round(avg(units_utilization_pct), 1) as avg_units_utilization_pct,

        -- Revenue impact
        sum(charges_at_risk) as charges_at_risk,
        count_if(has_prior_auth_denial) as encounters_with_prior_auth_claim_denial,
        sum(case when has_prior_auth_denial then encounter_charges else 0 end)
            as charges_on_prior_auth_claim_denials

    from auths
    group by hospital_id, payer_id, request_month
)

select
    {{ tenant_surrogate_key(['payer_id', 'request_month']) }} as prior_auth_metric_key,
    *,
    current_timestamp() as _dbt_updated_at
from aggregated
