{% macro calculate_hasbled_score(
    has_hypertension=false,
    has_abnormal_renal_function=false,
    has_abnormal_liver_function=false,
    has_stroke_history=false,
    has_bleeding_history=false,
    has_labile_inr=false,
    age_over_65=false,
    takes_antiplatelet=false,
    excessive_alcohol=false
) %}
/*
  HAS-BLED Bleeding Risk Score for Anticoagulation

  Used to assess bleeding risk in atrial fibrillation patients on anticoagulation.
  Score range: 0-9 (higher = higher bleeding risk)

  Interpretation:
  - 0-2: Low risk (1-2% annual bleeding risk)
  - 3-4: Moderate risk (3-4% annual bleeding risk)
  - ≥5: High risk (>5% annual bleeding risk)

  Note: High score doesn't mean avoid anticoagulation, but suggests
  increased monitoring and addressing modifiable risk factors.

  Scoring:
  - Hypertension (uncontrolled): 1 point
  - Abnormal renal function: 1 point
  - Abnormal liver function: 1 point
  - Stroke history: 1 point
  - Prior bleeding or predisposition: 1 point
  - Labile INR: 1 point
  - Elderly (age >65): 1 point
  - Drugs (antiplatelet/NSAIDs): 1 point
  - Alcohol (≥8 drinks/week): 1 point

  Usage:
    {{ calculate_hasbled_score(
        has_hypertension='uncontrolled_hypertension',
        has_abnormal_renal_function='renal_dysfunction',
        has_abnormal_liver_function='liver_dysfunction',
        has_stroke_history='prior_stroke',
        has_bleeding_history='prior_bleeding',
        has_labile_inr='labile_inr',
        age_over_65='age >= 65',
        takes_antiplatelet='on_antiplatelet',
        excessive_alcohol='alcohol_abuse'
    ) }} as hasbled_score
*/

(
  -- Hypertension (uncontrolled, >160 mmHg systolic)
  case when {{ has_hypertension }} then 1 else 0 end +

  -- Abnormal renal function (dialysis, transplant, Cr >2.26 mg/dL)
  case when {{ has_abnormal_renal_function }} then 1 else 0 end +

  -- Abnormal liver function (cirrhosis or bilirubin >2x normal or AST/ALT/AP >3x normal)
  case when {{ has_abnormal_liver_function }} then 1 else 0 end +

  -- Stroke history
  case when {{ has_stroke_history }} then 1 else 0 end +

  -- Prior major bleeding or predisposition to bleeding
  case when {{ has_bleeding_history }} then 1 else 0 end +

  -- Labile INR (unstable/high INRs, time in therapeutic range <60%)
  case when {{ has_labile_inr }} then 1 else 0 end +

  -- Elderly (age >65 years)
  case when {{ age_over_65 }} then 1 else 0 end +

  -- Drugs (antiplatelet agents or NSAIDs)
  case when {{ takes_antiplatelet }} then 1 else 0 end +

  -- Alcohol use (≥8 drinks per week)
  case when {{ excessive_alcohol }} then 1 else 0 end
)

{% endmacro %}


{% macro hasbled_risk_category(score_column) %}
/*
  Categorize HAS-BLED score into risk levels

  Usage:
    {{ hasbled_risk_category('hasbled_score') }} as bleeding_risk_category
*/

case
  when {{ score_column }} >= 5 then 'High Risk (≥5% annual bleeding risk)'
  when {{ score_column }} >= 3 then 'Moderate Risk (3-4% annual bleeding risk)'
  when {{ score_column }} >= 0 then 'Low Risk (1-2% annual bleeding risk)'
  else 'Unknown'
end

{% endmacro %}


{% macro hasbled_annual_bleeding_risk(score_column) %}
/*
  Convert HAS-BLED score to estimated annual major bleeding risk percentage

  Usage:
    {{ hasbled_annual_bleeding_risk('hasbled_score') }} as annual_bleeding_risk_pct
*/

case
  when {{ score_column }} = 0 then 1.13
  when {{ score_column }} = 1 then 1.02
  when {{ score_column }} = 2 then 1.88
  when {{ score_column }} = 3 then 3.74
  when {{ score_column }} = 4 then 8.70
  when {{ score_column }} >= 5 then 12.50
  else null
end

{% endmacro %}