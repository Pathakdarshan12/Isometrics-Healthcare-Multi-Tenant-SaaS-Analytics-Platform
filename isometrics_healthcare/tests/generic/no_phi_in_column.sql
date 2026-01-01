{% test no_phi_in_column(model, column_name) %}

--  {#
--    Test that column doesn't contain common PHI patterns
--    - SSN: XXX-XX-XXXX
--    - MRN: Hospital-specific patterns
--    - Phone: (XXX) XXX-XXXX
--    - Email: xxx@xxx.com
--  #}

  select
    {{ column_name }},
    count(*) as violation_count
  from {{ model }}
  where
    -- SSN pattern
    regexp_like({{ column_name }}, '\\d{3}-\\d{2}-\\d{4}')
    -- Phone pattern
    or regexp_like({{ column_name }}, '\\(\\d{3}\\) \\d{3}-\\d{4}')
    -- Email pattern (if not supposed to be there)
    or regexp_like({{ column_name }}, '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}')
  group by {{ column_name }}
  having count(*) > 0

{% endtest %}
