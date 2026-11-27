{#
  Charlson Comorbidity Index (CCI) — ICD-10 mapping after Quan et al.,
  "Coding algorithms for defining comorbidities in ICD-9-CM and ICD-10
  administrative data", Med Care 2005, with Charlson 1987 weights.

  Use charlson_condition() per diagnosis row, then sum charlson_weight() over the
  DISTINCT conditions per patient. Where a mild and severe form of the same
  disease are both present, only the severe form should count; the hierarchy is
  applied in int_clinical__comorbidity_index.
#}

{% macro charlson_condition(icd10_column) %}
  {%- set code = "upper(replace(" ~ icd10_column ~ ", '.', ''))" -%}
  case
    when left({{ code }}, 3) in ('I21', 'I22') or {{ code }} like 'I252%' then 'myocardial_infarction'
    when left({{ code }}, 3) in ('I43', 'I50') or left({{ code }}, 4) in ('I099', 'I110', 'I130', 'I132', 'I255', 'I420', 'I425', 'I426', 'I427', 'I428', 'I429', 'P290') then 'congestive_heart_failure'
    when left({{ code }}, 3) in ('I70', 'I71') or left({{ code }}, 4) in ('I731', 'I738', 'I739', 'I771', 'I790', 'I792', 'K551', 'K558', 'K559', 'Z958', 'Z959') then 'peripheral_vascular_disease'
    when left({{ code }}, 3) in ('G45', 'G46', 'I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') or left({{ code }}, 4) = 'H340' then 'cerebrovascular_disease'
    when left({{ code }}, 3) in ('F00', 'F01', 'F02', 'F03', 'G30') or left({{ code }}, 4) in ('F051', 'G311') then 'dementia'
    when left({{ code }}, 3) between 'J40' and 'J47' or left({{ code }}, 3) between 'J60' and 'J67' or left({{ code }}, 4) in ('I278', 'I279', 'J684', 'J701', 'J703') then 'chronic_pulmonary_disease'
    when left({{ code }}, 3) in ('M05', 'M06', 'M32', 'M33', 'M34') or left({{ code }}, 4) in ('M315', 'M351', 'M353', 'M360') then 'rheumatic_disease'
    when left({{ code }}, 3) in ('K25', 'K26', 'K27', 'K28') then 'peptic_ulcer_disease'
    when left({{ code }}, 4) in ('I850', 'I859', 'I864', 'I982', 'K704', 'K711', 'K721', 'K729', 'K765', 'K766', 'K767') then 'moderate_severe_liver_disease'
    when left({{ code }}, 3) in ('B18', 'K73', 'K74') or left({{ code }}, 4) in ('K700', 'K701', 'K702', 'K703', 'K709', 'K713', 'K714', 'K715', 'K717', 'K760', 'K762', 'K763', 'K764', 'K768', 'K769', 'Z944') then 'mild_liver_disease'
    when left({{ code }}, 4) in ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113', 'E114', 'E115', 'E117', 'E122', 'E123', 'E124', 'E125', 'E127', 'E132', 'E133', 'E134', 'E135', 'E137', 'E142', 'E143', 'E144', 'E145', 'E147') then 'diabetes_with_complications'
    when left({{ code }}, 3) in ('E10', 'E11', 'E12', 'E13', 'E14') then 'diabetes_without_complications'
    when left({{ code }}, 3) in ('G81', 'G82') or left({{ code }}, 4) in ('G041', 'G114', 'G801', 'G802', 'G830', 'G831', 'G832', 'G833', 'G834', 'G839') then 'hemiplegia_paraplegia'
    when left({{ code }}, 3) in ('N18', 'N19') or left({{ code }}, 4) in ('I120', 'I131', 'N032', 'N033', 'N034', 'N035', 'N036', 'N037', 'N052', 'N053', 'N054', 'N055', 'N056', 'N057', 'N250', 'Z490', 'Z491', 'Z492', 'Z940', 'Z992') then 'renal_disease'
    when left({{ code }}, 3) between 'C77' and 'C80' then 'metastatic_solid_tumor'
    when left({{ code }}, 3) between 'C00' and 'C26' or left({{ code }}, 3) between 'C30' and 'C34' or left({{ code }}, 3) between 'C37' and 'C41' or left({{ code }}, 3) in ('C43', 'C45', 'C46', 'C47', 'C48', 'C49', 'C50', 'C51', 'C52', 'C53', 'C54', 'C55', 'C56', 'C57', 'C58', 'C60', 'C61', 'C62', 'C63', 'C64', 'C65', 'C66', 'C67', 'C68', 'C69', 'C70', 'C71', 'C72', 'C73', 'C74', 'C75', 'C76', 'C81', 'C82', 'C83', 'C84', 'C85', 'C88', 'C90', 'C91', 'C92', 'C93', 'C94', 'C95', 'C96', 'C97') then 'malignancy'
    when left({{ code }}, 3) in ('B20', 'B21', 'B22', 'B24') then 'hiv_aids'
    else null
  end
{% endmacro %}


{% macro charlson_weight(condition_column) %}
  case {{ condition_column }}
    when 'myocardial_infarction' then 1
    when 'congestive_heart_failure' then 1
    when 'peripheral_vascular_disease' then 1
    when 'cerebrovascular_disease' then 1
    when 'dementia' then 1
    when 'chronic_pulmonary_disease' then 1
    when 'rheumatic_disease' then 1
    when 'peptic_ulcer_disease' then 1
    when 'mild_liver_disease' then 1
    when 'diabetes_without_complications' then 1
    when 'diabetes_with_complications' then 2
    when 'hemiplegia_paraplegia' then 2
    when 'renal_disease' then 2
    when 'malignancy' then 2
    when 'moderate_severe_liver_disease' then 3
    when 'metastatic_solid_tumor' then 6
    when 'hiv_aids' then 6
    else 0
  end
{% endmacro %}
