{% macro calculate_cha2ds2_vasc_score(
    age=none,
    gender=none,
    has_chf=false,
    has_hypertension=false,
    has_stroke_tia=false,
    has_vascular_disease=false,
    has_diabetes=false
) %}
/*
  CHA2DS2-VASc Score for Atrial Fibrillation Stroke Risk

  Used to determine anticoagulation need in atrial fibrillation patients.
  Score range: 0-9 (higher = higher stroke risk)

  Scoring:
  - Congestive Heart Failure: 1 point
  - Hypertension: 1 point
  - Age ≥75: 2 points
  - Diabetes: 1 point
  - Stroke/TIA/Thromboembolism: 2 points
  - Vascular disease: 1 point
  - Age 65-74: 1 point
  - Female gender: 1 point

  Interpretation:
  - 0 points (male) or 1 point (female): Low risk - No anticoagulation
  - 1 point (male): Consider anticoagulation
  - ≥2 points: Anticoagulation recommended

  Usage:
    {{ calculate_cha2ds2_vasc_score(
        age='age_years',
        gender='gender',
        has_chf='has_heart_failure',
        has_hypertension='has_hypertension',
        has_stroke_tia='has_stroke_history',
        has_vascular_disease='has_vascular_disease',
        has_diabetes='has_diabetes'
    ) }} as cha2ds2_vasc_score
*/

(
  -- Congestive Heart Failure (1 point)
  case when {{ has_chf }} then 1 else 0 end +

  -- Hypertension (1 point)
  case when {{ has_hypertension }} then 1 else 0 end +

  -- Age score (0-2 points)
  case
    {% if age %}
    when {{ age }} >= 75 then 2
    when {{ age }} >= 65 then 1
    {% endif %}
    else 0
  end +

  -- Diabetes (1 point)
  case when {{ has_diabetes }} then 1 else 0 end +

  -- Stroke/TIA/Thromboembolism (2 points)
  case when {{ has_stroke_tia }} then 2 else 0 end +

  -- Vascular disease (1 point)
  case when {{ has_vascular_disease }} then 1 else 0 end +

  -- Female gender (1 point)
  case
    {% if gender %}
    when upper({{ gender }}) = 'F' then 1
    {% endif %}
    else 0
  end
)

{% endmacro %}


{% macro cha2ds2_vasc_risk_category(score_column) %}
/*
  Categorize CHA2DS2-VASc score into risk levels

  Usage:
    {{ cha2ds2_vasc_risk_category('cha2ds2_vasc_score') }} as stroke_risk_category
*/

case
  when {{ score_column }} = 0 then 'Low Risk (No anticoagulation)'
  when {{ score_column }} = 1 then 'Low-Moderate Risk (Consider anticoagulation)'
  when {{ score_column }} >= 2 then 'High Risk (Anticoagulation recommended)'
  else 'Unknown'
end

{% endmacro %}


{% macro cha2ds2_vasc_annual_stroke_risk(score_column) %}
/*
  Convert CHA2DS2-VASc score to estimated annual stroke risk percentage

  Usage:
    {{ cha2ds2_vasc_annual_stroke_risk('cha2ds2_vasc_score') }} as annual_stroke_risk_pct
*/

case
  when {{ score_column }} = 0 then 0.0
  when {{ score_column }} = 1 then 1.3
  when {{ score_column }} = 2 then 2.2
  when {{ score_column }} = 3 then 3.2
  when {{ score_column }} = 4 then 4.0
  when {{ score_column }} = 5 then 6.7
  when {{ score_column }} = 6 then 9.8
  when {{ score_column }} = 7 then 9.6
  when {{ score_column }} = 8 then 6.7
  when {{ score_column }} = 9 then 15.2
  else null
end

{% endmacro %}