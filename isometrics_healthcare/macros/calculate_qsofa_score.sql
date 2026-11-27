{% macro calculate_qsofa_score(respiratory_rate, systolic_bp, altered_mentation) %}
  {#
    quick SOFA (qSOFA) — Sepsis-3 bedside screen (Seymour et al., JAMA 2016).
    One point each for:
      - respiratory rate >= 22 /min
      - systolic blood pressure <= 100 mmHg
      - altered mentation (GCS < 15); pass a boolean expression
    Range 0-3; a score >= 2 identifies patients at high risk of poor outcome.
    Missing inputs score 0 (consistent with bedside practice).

      {{ calculate_qsofa_score('respiratory_rate', 'systolic_bp', 'gcs_total < 15') }} as qsofa_score
  #}
  (
    case when {{ respiratory_rate }} >= 22 then 1 else 0 end
    + case when {{ systolic_bp }} <= 100 then 1 else 0 end
    + case when coalesce({{ altered_mentation }}, false) then 1 else 0 end
  )
{% endmacro %}
