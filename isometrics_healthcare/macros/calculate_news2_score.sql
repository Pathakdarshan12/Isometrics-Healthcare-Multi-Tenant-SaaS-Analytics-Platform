{% macro calculate_news2_score(respiratory_rate, spo2, on_supplemental_oxygen, temperature_c, systolic_bp, heart_rate, consciousness_alert) %}
  {#
    National Early Warning Score 2 (Royal College of Physicians, 2017), SpO2 scale 1.

    Parameters are column names / expressions:
      respiratory_rate        breaths/min
      spo2                    %
      on_supplemental_oxygen  boolean
      temperature_c           degrees Celsius
      systolic_bp             mmHg
      heart_rate              beats/min
      consciousness_alert     boolean; false = new confusion / V / P / U on ACVPU

    Range 0-20. Clinical response thresholds: 0-4 low, 5-6 medium (or any single
    parameter scoring 3), >= 7 high. Use news2_risk_level() for the band.
    Missing parameters score 0.
  #}
  (
    -- Respiratory rate
    case
      when {{ respiratory_rate }} is null then 0
      when {{ respiratory_rate }} <= 8 then 3
      when {{ respiratory_rate }} <= 11 then 1
      when {{ respiratory_rate }} <= 20 then 0
      when {{ respiratory_rate }} <= 24 then 2
      else 3
    end
    -- SpO2 (scale 1)
    + case
      when {{ spo2 }} is null then 0
      when {{ spo2 }} <= 91 then 3
      when {{ spo2 }} <= 93 then 2
      when {{ spo2 }} <= 95 then 1
      else 0
    end
    -- Supplemental oxygen
    + case when coalesce({{ on_supplemental_oxygen }}, false) then 2 else 0 end
    -- Temperature
    + case
      when {{ temperature_c }} is null then 0
      when {{ temperature_c }} <= 35.0 then 3
      when {{ temperature_c }} <= 36.0 then 1
      when {{ temperature_c }} <= 38.0 then 0
      when {{ temperature_c }} <= 39.0 then 1
      else 2
    end
    -- Systolic blood pressure
    + case
      when {{ systolic_bp }} is null then 0
      when {{ systolic_bp }} <= 90 then 3
      when {{ systolic_bp }} <= 100 then 2
      when {{ systolic_bp }} <= 110 then 1
      when {{ systolic_bp }} <= 219 then 0
      else 3
    end
    -- Heart rate
    + case
      when {{ heart_rate }} is null then 0
      when {{ heart_rate }} <= 40 then 3
      when {{ heart_rate }} <= 50 then 1
      when {{ heart_rate }} <= 90 then 0
      when {{ heart_rate }} <= 110 then 1
      when {{ heart_rate }} <= 130 then 2
      else 3
    end
    -- Consciousness (ACVPU)
    + case when {{ consciousness_alert }} = false then 3 else 0 end
  )
{% endmacro %}


{% macro news2_risk_level(news2_score_column) %}
  {# RCP clinical risk band for an aggregate NEWS2 score. #}
  case
    when {{ news2_score_column }} is null then 'Unknown'
    when {{ news2_score_column }} >= 7 then 'High'
    when {{ news2_score_column }} >= 5 then 'Medium'
    else 'Low'
  end
{% endmacro %}
