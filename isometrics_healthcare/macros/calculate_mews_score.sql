{% macro calculate_mews_score(
    systolic_bp=none,
    heart_rate=none,
    respiratory_rate=none,
    temperature_c=none,
    avpu_score=none
) %}
/*
  Modified Early Warning Score (MEWS)

  Used for early detection of patient deterioration on general wards.
  Score range: 0-14 (higher = higher risk)

  Triggers:
  - MEWS ≥5: Urgent medical review
  - MEWS ≥3: Increased monitoring

  Components:
  1. Systolic Blood Pressure
  2. Heart Rate
  3. Respiratory Rate
  4. Temperature
  5. AVPU (Alert, Voice, Pain, Unresponsive)

  Usage:
    {{ calculate_mews_score(
        systolic_bp='systolic_bp',
        heart_rate='heart_rate_bpm',
        respiratory_rate='respiratory_rate',
        temperature_c='temperature_celsius',
        avpu_score='avpu_score'
    ) }} as mews_score
*/

(
  -- Systolic Blood Pressure Score (0-3 points)
  case
    {% if systolic_bp %}
    when {{ systolic_bp }} >= 200 then 2
    when {{ systolic_bp }} >= 101 then 0
    when {{ systolic_bp }} >= 81 then 1
    when {{ systolic_bp }} >= 71 then 2
    when {{ systolic_bp }} < 71 then 3
    {% endif %}
    else 0
  end +

  -- Heart Rate Score (0-3 points)
  case
    {% if heart_rate %}
    when {{ heart_rate }} >= 130 then 2
    when {{ heart_rate }} >= 111 then 1
    when {{ heart_rate }} >= 51 then 0
    when {{ heart_rate }} >= 41 then 1
    when {{ heart_rate }} < 41 then 2
    {% endif %}
    else 0
  end +

  -- Respiratory Rate Score (0-3 points)
  case
    {% if respiratory_rate %}
    when {{ respiratory_rate }} >= 30 then 3
    when {{ respiratory_rate }} >= 21 then 2
    when {{ respiratory_rate }} >= 15 then 0
    when {{ respiratory_rate }} >= 9 then 1
    when {{ respiratory_rate }} < 9 then 2
    {% endif %}
    else 0
  end +

  -- Temperature Score (0-2 points)
  case
    {% if temperature_c %}
    when {{ temperature_c }} >= 38.5 then 2
    when {{ temperature_c }} >= 35 then 0
    when {{ temperature_c }} < 35 then 2
    {% endif %}
    else 0
  end +

  -- AVPU Score (0-3 points)
  -- A = Alert (0), V = Voice (1), P = Pain (2), U = Unresponsive (3)
  case
    {% if avpu_score %}
    when upper({{ avpu_score }}) = 'A' then 0
    when upper({{ avpu_score }}) = 'V' then 1
    when upper({{ avpu_score }}) = 'P' then 2
    when upper({{ avpu_score }}) = 'U' then 3
    {% endif %}
    else 0
  end
)

{% endmacro %}


{% macro mews_risk_category(score_column) %}
/*
  Categorize MEWS score into risk/action levels

  Usage:
    {{ mews_risk_category('mews_score') }} as mews_risk_level
*/

case
  when {{ score_column }} >= 5 then 'Critical (Urgent medical review required)'
  when {{ score_column }} >= 3 then 'High (Increase monitoring frequency)'
  when {{ score_column }} >= 1 then 'Medium (Continue monitoring)'
  when {{ score_column }} = 0 then 'Low (Routine monitoring)'
  else 'Unknown'
end

{% endmacro %}