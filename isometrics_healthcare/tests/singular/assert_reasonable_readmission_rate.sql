-- Test that 30-day readmission rate is within expected range (1-15%)

with readmission_stats as (
    select
        count(*) as total_encounters,
        sum(case when is_readmission then 1 else 0 end) as readmissions,
        case
            when count(*) = 0 then null
            else (sum(case when is_readmission then 1 else 0 end) * 100.0 / count(*))
        end as readmission_rate
    from {{ ref('stg_healthcare__encounters') }}
    where encounter_type = 'Inpatient'
)

select *
from readmission_stats
where
    total_encounters >= 1000  -- Only test if we have meaningful data
    and (
        readmission_rate < 1      -- Too low - likely broken logic
        or readmission_rate > 15  -- Too high - data quality issue
        or readmission_rate is null
    )