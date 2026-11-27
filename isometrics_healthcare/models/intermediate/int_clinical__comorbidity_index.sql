{{
  config(
    materialized='ephemeral',
    tags=['intermediate', 'silver', 'clinical', 'risk']
  )
}}

/*
  Charlson Comorbidity Index per patient (Quan 2005 ICD-10 mapping, Charlson 1987 weights).

  Diagnosis sources: active problem-list entries + encounter primary diagnoses.
  Hierarchy rules (only the more severe form counts):
    - diabetes with complications      supersedes diabetes without complications
    - moderate/severe liver disease    supersedes mild liver disease
    - metastatic solid tumor           supersedes malignancy
  Age-adjusted CCI adds 1 point per decade from age 50 (max 4).
  Grain: one row per (hospital_id, patient_id).
*/

{% set conditions = {
    'myocardial_infarction': 1,
    'congestive_heart_failure': 1,
    'peripheral_vascular_disease': 1,
    'cerebrovascular_disease': 1,
    'dementia': 1,
    'chronic_pulmonary_disease': 1,
    'rheumatic_disease': 1,
    'peptic_ulcer_disease': 1,
    'mild_liver_disease': 1,
    'diabetes_without_complications': 1,
    'diabetes_with_complications': 2,
    'hemiplegia_paraplegia': 2,
    'renal_disease': 2,
    'malignancy': 2,
    'moderate_severe_liver_disease': 3,
    'metastatic_solid_tumor': 6,
    'hiv_aids': 6
} %}

{% set superseded_by = {
    'diabetes_without_complications': 'diabetes_with_complications',
    'mild_liver_disease': 'moderate_severe_liver_disease',
    'malignancy': 'metastatic_solid_tumor'
} %}

with patients as (
    select hospital_id, patient_id, age_years
    from {{ ref('stg_healthcare__patients') }}
),

diagnoses as (
    select hospital_id, patient_id, diagnosis_code
    from {{ ref('stg_healthcare__problem_list') }}
    where is_active

    union

    select hospital_id, patient_id, primary_diagnosis_code as diagnosis_code
    from {{ ref('stg_healthcare__encounters') }}
    where primary_diagnosis_code is not null
),

mapped as (
    select
        hospital_id,
        patient_id,
        {{ charlson_condition('diagnosis_code') }} as charlson_condition
    from diagnoses
),

condition_flags as (
    select
        hospital_id,
        patient_id,
        {% for condition in conditions %}
        boolor_agg(charlson_condition = '{{ condition }}') as has_{{ condition }}{{ "," if not loop.last }}
        {% endfor %}
    from mapped
    where charlson_condition is not null
    group by hospital_id, patient_id
),

scored as (
    select
        p.hospital_id,
        p.patient_id,
        p.age_years,

        {% for condition in conditions %}
        coalesce(f.has_{{ condition }}, false) as has_{{ condition }},
        {% endfor %}

        (
        {% for condition, weight in conditions.items() %}
            case
                when coalesce(f.has_{{ condition }}, false)
                {% if condition in superseded_by %}
                    and not coalesce(f.has_{{ superseded_by[condition] }}, false)
                {% endif %}
                then {{ weight }} else 0
            end
            {{ "+" if not loop.last }}
        {% endfor %}
        ) as charlson_index,

        (
        {% for condition in conditions %}
            case when coalesce(f.has_{{ condition }}, false) then 1 else 0 end
            {{ "+" if not loop.last }}
        {% endfor %}
        ) as charlson_condition_count,

        case
            when p.age_years >= 80 then 4
            when p.age_years >= 70 then 3
            when p.age_years >= 60 then 2
            when p.age_years >= 50 then 1
            else 0
        end as charlson_age_points

    from patients p
    left join condition_flags f
        on p.patient_id = f.patient_id
        and p.hospital_id = f.hospital_id
)

select
    *,
    charlson_index + charlson_age_points as charlson_age_adjusted_index,
    case
        when charlson_index = 0 then 'None'
        when charlson_index <= 2 then 'Mild'
        when charlson_index <= 4 then 'Moderate'
        else 'Severe'
    end as charlson_severity
from scored
