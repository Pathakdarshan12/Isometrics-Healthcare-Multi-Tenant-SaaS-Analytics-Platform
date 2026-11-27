{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'care_coordination']
  )
}}

/*
  Referrals with discharge context and access-to-care SLAs.
  Grain: one row per referral (referral_id).

  Scheduling SLA by urgency (days from referral to appointment):
    EMERGENT 2, URGENT 7, ROUTINE 30
  A referral "closes the loop" when it is completed and any required
  follow-up has been documented.
*/

with referrals as (
    select * from {{ ref('stg_healthcare__referrals') }}
),

encounters as (
    select
        encounter_id,
        hospital_id,
        encounter_type,
        discharge_date,
        discharge_disposition,
        primary_diagnosis_code,
        is_readmission
    from {{ ref('stg_healthcare__encounters') }}
),

providers as (
    select provider_id, hospital_id, specialty as referring_provider_specialty
    from {{ ref('stg_healthcare__providers') }}
),

joined as (
    select
        r.referral_id,
        r.hospital_id,
        r.patient_id,
        r.encounter_id,
        r.referring_provider_id,
        p.referring_provider_specialty,
        r.referred_to_provider_id,
        r.referred_to_facility,

        r.referral_type,
        r.specialty as referred_specialty,
        r.urgency,
        r.referral_status,
        r.is_completed,
        r.is_pending,
        r.is_cancelled,

        r.referral_date,
        date_trunc('month', r.referral_date) as referral_month,
        r.appointment_date,
        r.completion_date,
        r.days_to_appointment,
        r.days_to_completion,

        r.follow_up_required,
        r.follow_up_completed,
        r.follow_up_overdue,
        r.overdue_for_appointment,

        e.encounter_type as source_encounter_type,
        e.discharge_disposition,
        e.primary_diagnosis_code,
        e.is_readmission as source_encounter_is_readmission,

        case upper(r.urgency)
            when 'EMERGENT' then 2
            when 'URGENT' then 7
            else 30
        end as scheduling_sla_days

    from referrals r
    left join encounters e
        on r.encounter_id = e.encounter_id
        and r.hospital_id = e.hospital_id
    left join providers p
        on r.referring_provider_id = p.provider_id
        and r.hospital_id = p.hospital_id
)

select
    *,
    case
        when days_to_appointment is null then null
        else days_to_appointment <= scheduling_sla_days
    end as scheduled_within_sla,
    coalesce(is_completed and (not coalesce(follow_up_required, false) or coalesce(follow_up_completed, false)), false)
        as is_closed_loop
from joined
