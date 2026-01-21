{% macro calculate_apache_ii_score(
    age=none,
    temperature_c=none,
    map_mmhg=none,
    heart_rate=none,
    respiratory_rate=none,
    pao2=none,
    fio2=none,
    arterial_ph=none,
    serum_sodium=none,
    serum_potassium=none,
    serum_creatinine=none,
    hematocrit=none,
    wbc_count=none,
    gcs_score=none,
    has_chronic_disease=false,
    admission_type='elective'
) %}
/*
  APACHE II (Acute Physiology and Chronic Health Evaluation II) Score

  Predicts mortality risk in ICU patients.
  Score range: 0-71 (higher = higher mortality risk)

  Components:
  1. Acute Physiology Score (12 variables, 0-60 points)
  2. Age points (0-6 points)
  3. Chronic Health points (0-5 points)

  Mortality estimates:
  - 0-4: <4% mortality
  - 5-9: 4% mortality
  - 10-14: 8% mortality
  - 15-19: 15% mortality
  - 20-24: 25% mortality
  - 25-29: 40% mortality
  - 30-34: 55% mortality
  - >34: >85% mortality

  Usage:
    {{ calculate_apache_ii_score(
        age='age_years',
        temperature_c='temperature_celsius',
        map_mmhg='mean_arterial_pressure',
        heart_rate='heart_rate_bpm',
        respiratory_rate='respiratory_rate',
        arterial_ph='arterial_ph',
        serum_sodium='sodium',
        serum_potassium='potassium',
        serum_creatinine='creatinine',
        hematocrit='hct',
        wbc_count='wbc',
        gcs_score='glasgow_coma_scale',
        has_chronic_disease='has_chronic_organ_insufficiency',
        admission_type='admission_type'
    ) }} as apache_ii_score
*/

(
  -- Temperature Score (rectal, 0-4 points)
  case
    {% if temperature_c %}
    when {{ temperature_c }} >= 41 then 4
    when {{ temperature_c }} >= 39 then 3
    when {{ temperature_c }} >= 38.5 then 1
    when {{ temperature_c }} >= 36 then 0
    when {{ temperature_c }} >= 34 then 1
    when {{ temperature_c }} >= 32 then 2
    when {{ temperature_c }} >= 30 then 3
    when {{ temperature_c }} < 30 then 4
    {% endif %}
    else 0
  end +

  -- Mean Arterial Pressure Score (0-4 points)
  case
    {% if map_mmhg %}
    when {{ map_mmhg }} >= 160 then 4
    when {{ map_mmhg }} >= 130 then 3
    when {{ map_mmhg }} >= 110 then 2
    when {{ map_mmhg }} >= 70 then 0
    when {{ map_mmhg }} >= 50 then 2
    when {{ map_mmhg }} < 50 then 4
    {% endif %}
    else 0
  end +

  -- Heart Rate Score (0-4 points)
  case
    {% if heart_rate %}
    when {{ heart_rate }} >= 180 then 4
    when {{ heart_rate }} >= 140 then 3
    when {{ heart_rate }} >= 110 then 2
    when {{ heart_rate }} >= 70 then 0
    when {{ heart_rate }} >= 55 then 2
    when {{ heart_rate }} >= 40 then 3
    when {{ heart_rate }} < 40 then 4
    {% endif %}
    else 0
  end +

  -- Respiratory Rate Score (0-4 points)
  case
    {% if respiratory_rate %}
    when {{ respiratory_rate }} >= 50 then 4
    when {{ respiratory_rate }} >= 35 then 3
    when {{ respiratory_rate }} >= 25 then 1
    when {{ respiratory_rate }} >= 12 then 0
    when {{ respiratory_rate }} >= 10 then 1
    when {{ respiratory_rate }} >= 6 then 2
    when {{ respiratory_rate }} < 6 then 4
    {% endif %}
    else 0
  end +

  -- Oxygenation Score (A-a gradient if FiO2 ≥0.5, else PaO2) (0-4 points)
  case
    {% if pao2 and fio2 %}
    when {{ fio2 }} >= 0.5 then
      case
        when (713 * {{ fio2 }}) - {{ pao2 }} >= 500 then 4
        when (713 * {{ fio2 }}) - {{ pao2 }} >= 350 then 3
        when (713 * {{ fio2 }}) - {{ pao2 }} >= 200 then 2
        when (713 * {{ fio2 }}) - {{ pao2 }} < 200 then 0
      end
    when {{ fio2 }} < 0.5 then
      case
        when {{ pao2 }} >= 70 then 0
        when {{ pao2 }} >= 61 then 1
        when {{ pao2 }} >= 55 then 3
        when {{ pao2 }} < 55 then 4
      end
    {% endif %}
    else 0
  end +

  -- Arterial pH Score (0-4 points)
  case
    {% if arterial_ph %}
    when {{ arterial_ph }} >= 7.7 then 4
    when {{ arterial_ph }} >= 7.6 then 3
    when {{ arterial_ph }} >= 7.5 then 1
    when {{ arterial_ph }} >= 7.33 then 0
    when {{ arterial_ph }} >= 7.25 then 2
    when {{ arterial_ph }} >= 7.15 then 3
    when {{ arterial_ph }} < 7.15 then 4
    {% endif %}
    else 0
  end +

  -- Serum Sodium Score (0-4 points)
  case
    {% if serum_sodium %}
    when {{ serum_sodium }} >= 180 then 4
    when {{ serum_sodium }} >= 160 then 3
    when {{ serum_sodium }} >= 155 then 2
    when {{ serum_sodium }} >= 150 then 1
    when {{ serum_sodium }} >= 130 then 0
    when {{ serum_sodium }} >= 120 then 2
    when {{ serum_sodium }} >= 111 then 3
    when {{ serum_sodium }} < 111 then 4
    {% endif %}
    else 0
  end +

  -- Serum Potassium Score (0-4 points)
  case
    {% if serum_potassium %}
    when {{ serum_potassium }} >= 7 then 4
    when {{ serum_potassium }} >= 6 then 3
    when {{ serum_potassium }} >= 5.5 then 1
    when {{ serum_potassium }} >= 3.5 then 0
    when {{ serum_potassium }} >= 3 then 1
    when {{ serum_potassium }} >= 2.5 then 2
    when {{ serum_potassium }} < 2.5 then 4
    {% endif %}
    else 0
  end +

  -- Serum Creatinine Score (0-4 points, doubled if acute renal failure)
  case
    {% if serum_creatinine %}
    when {{ serum_creatinine }} >= 3.5 then 4
    when {{ serum_creatinine }} >= 2 then 3
    when {{ serum_creatinine }} >= 1.5 then 2
    when {{ serum_creatinine }} < 0.6 then 2
    else 0
    {% endif %}
    else 0
  end +

  -- Hematocrit Score (0-4 points)
  case
    {% if hematocrit %}
    when {{ hematocrit }} >= 60 then 4
    when {{ hematocrit }} >= 50 then 2
    when {{ hematocrit }} >= 46 then 1
    when {{ hematocrit }} >= 30 then 0
    when {{ hematocrit }} >= 20 then 2
    when {{ hematocrit }} < 20 then 4
    {% endif %}
    else 0
  end +

  -- White Blood Cell Count Score (0-4 points, in thousands)
  case
    {% if wbc_count %}
    when {{ wbc_count }} >= 40 then 4
    when {{ wbc_count }} >= 20 then 2
    when {{ wbc_count }} >= 15 then 1
    when {{ wbc_count }} >= 3 then 0
    when {{ wbc_count }} >= 1 then 2
    when {{ wbc_count }} < 1 then 4
    {% endif %}
    else 0
  end +

  -- Glasgow Coma Scale Score (0-12 points)
  -- APACHE II uses 15 - actual GCS
  case
    {% if gcs_score %}
    when {{ gcs_score }} = 15 then 0
    when {{ gcs_score }} = 14 then 1
    when {{ gcs_score }} = 13 then 2
    when {{ gcs_score }} = 12 then 3
    when {{ gcs_score }} = 11 then 4
    when {{ gcs_score }} = 10 then 5
    when {{ gcs_score }} = 9 then 6
    when {{ gcs_score }} = 8 then 7
    when {{ gcs_score }} = 7 then 8
    when {{ gcs_score }} = 6 then 9
    when {{ gcs_score }} = 5 then 10
    when {{ gcs_score }} = 4 then 11
    when {{ gcs_score }} = 3 then 12
    {% endif %}
    else 0
  end +

  -- Age Points (0-6 points)
  case
    {% if age %}
    when {{ age }} >= 75 then 6
    when {{ age }} >= 65 then 5
    when {{ age }} >= 55 then 3
    when {{ age }} >= 45 then 2
    {% endif %}
    else 0
  end +

  -- Chronic Health Points (0-5 points)
  case
    when {{ has_chronic_disease }} then
      case
        when upper({{ admission_type }}) in ('EMERGENCY', 'URGENT') then 5
        else 2  -- Elective surgery
      end
    else 0
  end
)

{% endmacro %}


{% macro apache_ii_mortality_risk(score_column) %}
/*
  Convert APACHE II score to estimated mortality risk percentage

  Usage:
    {{ apache_ii_mortality_risk('apache_ii_score') }} as predicted_mortality_pct
*/

case
  when {{ score_column }} <= 4 then 4
  when {{ score_column }} <= 9 then 8
  when {{ score_column }} <= 14 then 15
  when {{ score_column }} <= 19 then 25
  when {{ score_column }} <= 24 then 40
  when {{ score_column }} <= 29 then 55
  when {{ score_column }} <= 34 then 73
  when {{ score_column }} > 34 then 85
  else null
end

{% endmacro %}