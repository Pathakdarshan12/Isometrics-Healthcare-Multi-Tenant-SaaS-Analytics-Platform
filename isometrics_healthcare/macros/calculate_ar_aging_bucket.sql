{% macro calculate_ar_aging_bucket(days_outstanding_column) %}
  {#
    Standard accounts-receivable aging buckets used in revenue cycle reporting.

      {{ calculate_ar_aging_bucket("datediff('day', transaction_date, current_date())") }} as ar_bucket
  #}
  case
    when {{ days_outstanding_column }} is null then 'Unknown'
    when {{ days_outstanding_column }} <= 30 then '0-30'
    when {{ days_outstanding_column }} <= 60 then '31-60'
    when {{ days_outstanding_column }} <= 90 then '61-90'
    when {{ days_outstanding_column }} <= 120 then '91-120'
    else '120+'
  end
{% endmacro %}
