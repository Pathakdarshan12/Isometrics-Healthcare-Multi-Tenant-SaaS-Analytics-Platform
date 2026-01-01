-- Test that 30-day readmission rate is within expected range (1-10%)

with readmission_stats as (
    select
        count(*) as total_encounters,
        sum(case when is_readmission then 1 else 0 end) as readmissions,
        (readmissions * 100.0 / total_encounters) as readmission_rate
    from {{ ref('stg_healthcare__encounters') }}
    where encounter_type = 'Inpatient'
)

select *
from readmission_stats
where
    readmission_rate < 1  -- Too low - data quality issue?
    or readmission_rate > 10  -- Too high - serious quality problem