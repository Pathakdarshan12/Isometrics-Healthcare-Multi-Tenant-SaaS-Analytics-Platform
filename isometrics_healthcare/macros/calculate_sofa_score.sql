{% macro calculate_sofa_score(
    pao2_fio2_ratio=none,
    platelets=none,
    bilirubin=none,
    map_mmhg=none,
    gcs_score=none,
    creatinine=none,
    urine_output_ml=none
) %}
/*
  Sequential Organ Failure Assessment (SOFA) Score

  Used to track organ dysfunction in ICU patients with sepsis.
  Score range: 0-24 (higher is worse)

  Components:
  1. Respiration (PaO2/FiO2 ratio)
  2. Coagulation (Platelets)
  3. Liver (Bilirubin)
  4. Cardiovascular (MAP or vasopressor use)
  5. Central Nervous System (Glasgow Coma Scale)
  6. Renal (Creatinine or urine output)

  Usage:
    {{ calculate_sofa_score(
        pao2_fio2_ratio='pao2_fio2',
        platelets='platelet_count',
        bilirubin='total_bilirubin',
        map_mmhg='mean_arterial_pressure',
        gcs_score='glasgow_coma_scale',
        creatinine='serum_creatinine',
        urine_output_ml='urine_output_24hr'
    ) }} as sofa_score
*/

(
  -- Respiration Score (0-4)
  case
    {% if pao2_fio2_ratio %}
    when {{ pao2_fio2_ratio }} >= 400 then 0
    when {{ pao2_fio2_ratio }} >= 300 then 1
    when {{ pao2_fio2_ratio }} >= 200 then 2
    when {{ pao2_fio2_ratio }} >= 100 then 3
    when {{ pao2_fio2_ratio }} < 100 then 4
    {% endif %}
    else 0
  end +

  -- Coagulation Score (0-4) - Platelets in thousands
  case
    {% if platelets %}
    when {{ platelets }} >= 150 then 0
    when {{ platelets }} >= 100 then 1
    when {{ platelets }} >= 50 then 2
    when {{ platelets }} >= 20 then 3
    when {{ platelets }} < 20 then 4
    {% endif %}
    else 0
  end +

  -- Liver Score (0-4) - Bilirubin in mg/dL
  case
    {% if bilirubin %}
    when {{ bilirubin }} < 1.2 then 0
    when {{ bilirubin }} < 2.0 then 1
    when {{ bilirubin }} < 6.0 then 2
    when {{ bilirubin }} < 12.0 then 3
    when {{ bilirubin }} >= 12.0 then 4
    {% endif %}
    else 0
  end +

  -- Cardiovascular Score (0-4) - MAP in mmHg
  case
    {% if map_mmhg %}
    when {{ map_mmhg }} >= 70 then 0
    when {{ map_mmhg }} < 70 then 1
    -- Note: Scores 2-4 require vasopressor data (dopamine, dobutamine, epinephrine, norepinephrine)
    -- This would need additional fields to fully implement
    {% endif %}
    else 0
  end +

  -- Central Nervous System Score (0-4) - Glasgow Coma Scale
  case
    {% if gcs_score %}
    when {{ gcs_score }} = 15 then 0
    when {{ gcs_score }} between 13 and 14 then 1
    when {{ gcs_score }} between 10 and 12 then 2
    when {{ gcs_score }} between 6 and 9 then 3
    when {{ gcs_score }} < 6 then 4
    {% endif %}
    else 0
  end +

  -- Renal Score (0-4) - Creatinine in mg/dL or Urine Output in mL/day
  case
    {% if creatinine %}
    when {{ creatinine }} < 1.2 then 0
    when {{ creatinine }} < 2.0 then 1
    when {{ creatinine }} < 3.5 then 2
    when {{ creatinine }} < 5.0 then 3
    when {{ creatinine }} >= 5.0 then 4
    {% elif urine_output_ml %}
    when {{ urine_output_ml }} >= 500 then 0
    when {{ urine_output_ml }} >= 200 then 3
    when {{ urine_output_ml }} < 200 then 4
    {% endif %}
    else 0
  end
)

{% endmacro %}