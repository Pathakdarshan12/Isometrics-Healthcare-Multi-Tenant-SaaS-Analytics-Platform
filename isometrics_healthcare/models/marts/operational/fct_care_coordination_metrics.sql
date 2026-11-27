{{
  config(
    materialized='table',
    tags=['marts', 'operational', 'care_coordination', 'daily'],
    cluster_by=['hospital_id', 'metric_month'],
    schema='marts',
    post_hook=["{{ apply_rls_policy() }}"]
  )
}}

/*
  Care coordination KPIs: referral access/closure and care plan management.
  Grain: hospital_id x metric_month
    - referral metrics are bucketed by referral month
    - care plan metrics are bucketed by plan start month
*/

with referrals as (
    select * from {{ ref('int_care_coordination__referrals_enriched') }}
),

care_plans as (
    select * from {{ ref('stg_healthcare__care_plans') }}
),

comorbidity as (
    select hospital_id, patient_id, charlson_index
    from {{ ref('int_clinical__comorbidity_index') }}
),

referral_metrics as (
    select
        r.hospital_id,
        r.referral_month as metric_month,

        count(*) as referrals_created,
        count_if(upper(r.urgency) in ('URGENT', 'EMERGENT')) as urgent_referrals,
        count_if(r.referral_type = 'SPECIALIST') as specialist_referrals,
        count_if(r.referral_type in ('HOME_HEALTH', 'SNF', 'DME')) as post_acute_referrals,

        count_if(r.is_completed) as referrals_completed,
        count_if(r.is_cancelled) as referrals_cancelled,
        count_if(r.overdue_for_appointment) as referrals_overdue_for_scheduling,
        count_if(r.follow_up_overdue) as referrals_follow_up_overdue,

        {{ calculate_percentage('count_if(r.is_completed)', 'count(*) - count_if(r.is_cancelled)') }}
            as referral_completion_rate_pct,
        {{ calculate_percentage('count_if(r.is_closed_loop)', 'count_if(r.is_completed)') }}
            as referral_closed_loop_rate_pct,
        {{ calculate_percentage('count_if(r.scheduled_within_sla)', 'count_if(r.scheduled_within_sla is not null)') }}
            as scheduled_within_sla_pct,
        round(median(r.days_to_appointment), 1) as median_days_to_appointment,

        round(avg(c.charlson_index), 2) as avg_charlson_index_referred
    from referrals r
    left join comorbidity c
        on r.patient_id = c.patient_id
        and r.hospital_id = c.hospital_id
    group by r.hospital_id, r.referral_month
),

care_plan_metrics as (
    select
        hospital_id,
        date_trunc('month', start_date) as metric_month,

        count(*) as care_plans_started,
        count_if(is_active_plan) as care_plans_active,
        count_if(is_completed_plan) as care_plans_completed,
        count_if(is_discontinued_plan) as care_plans_discontinued,
        count_if(overdue_for_evaluation) as care_plans_overdue_for_evaluation,
        count_if(past_target_date) as care_plans_past_target_date,

        {{ calculate_percentage('count_if(is_completed_plan)', 'count_if(is_completed_plan or is_discontinued_plan)') }}
            as care_plan_goal_completion_rate_pct,
        round(avg(case when is_completed_plan then plan_duration_days end), 1)
            as avg_completed_plan_duration_days
    from care_plans
    group by hospital_id, date_trunc('month', start_date)
),

combined as (
    select
        coalesce(r.hospital_id, cp.hospital_id) as hospital_id,
        coalesce(r.metric_month, cp.metric_month) as metric_month,

        coalesce(r.referrals_created, 0) as referrals_created,
        coalesce(r.urgent_referrals, 0) as urgent_referrals,
        coalesce(r.specialist_referrals, 0) as specialist_referrals,
        coalesce(r.post_acute_referrals, 0) as post_acute_referrals,
        coalesce(r.referrals_completed, 0) as referrals_completed,
        coalesce(r.referrals_cancelled, 0) as referrals_cancelled,
        coalesce(r.referrals_overdue_for_scheduling, 0) as referrals_overdue_for_scheduling,
        coalesce(r.referrals_follow_up_overdue, 0) as referrals_follow_up_overdue,
        r.referral_completion_rate_pct,
        r.referral_closed_loop_rate_pct,
        r.scheduled_within_sla_pct,
        r.median_days_to_appointment,
        r.avg_charlson_index_referred,

        coalesce(cp.care_plans_started, 0) as care_plans_started,
        coalesce(cp.care_plans_active, 0) as care_plans_active,
        coalesce(cp.care_plans_completed, 0) as care_plans_completed,
        coalesce(cp.care_plans_discontinued, 0) as care_plans_discontinued,
        coalesce(cp.care_plans_overdue_for_evaluation, 0) as care_plans_overdue_for_evaluation,
        coalesce(cp.care_plans_past_target_date, 0) as care_plans_past_target_date,
        cp.care_plan_goal_completion_rate_pct,
        cp.avg_completed_plan_duration_days

    from referral_metrics r
    full outer join care_plan_metrics cp
        on r.hospital_id = cp.hospital_id
        and r.metric_month = cp.metric_month
)

select
    {{ tenant_surrogate_key(['metric_month']) }} as care_coordination_key,
    *,
    current_timestamp() as _dbt_updated_at
from combined
