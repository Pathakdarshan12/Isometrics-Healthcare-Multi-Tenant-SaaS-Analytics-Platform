-- ============================================
-- Provider Performance Analysis
-- Ad-hoc analysis for identifying top/bottom performers
-- ============================================

WITH provider_stats AS (
    SELECT
        hospital_id,
        provider_full_name,
        specialty,
        total_encounters,
        readmission_rate_pct,
        mortality_rate_pct,
        avg_length_of_stay,
        total_charges,
        readmission_performance,
        productivity_category
    FROM {{ ref('fct_provider_performance') }}
),

-- Top performers by readmission rate
top_performers AS (
    SELECT
        'Top 10 - Lowest Readmissions' as category,
        provider_full_name,
        specialty,
        readmission_rate_pct,
        total_encounters
    FROM provider_stats
    WHERE total_encounters >= 50  -- Minimum volume threshold
    ORDER BY readmission_rate_pct ASC
    LIMIT 10
),

-- Bottom performers
bottom_performers AS (
    SELECT
        'Bottom 10 - Highest Readmissions' as category,
        provider_full_name,
        specialty,
        readmission_rate_pct,
        total_encounters
    FROM provider_stats
    WHERE total_encounters >= 50
    ORDER BY readmission_rate_pct DESC
    LIMIT 10
),

-- Specialty benchmarks
specialty_benchmarks AS (
    SELECT
        specialty,
        COUNT(DISTINCT provider_full_name) as provider_count,
        AVG(readmission_rate_pct) as avg_readmission_rate,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY readmission_rate_pct) as median_readmission_rate,
        AVG(total_encounters) as avg_volume
    FROM provider_stats
    GROUP BY specialty
    ORDER BY avg_readmission_rate
)

-- Combine results
SELECT * FROM top_performers
UNION ALL
SELECT * FROM bottom_performers
UNION ALL
SELECT
    'Specialty Benchmark' as category,
    specialty as provider_full_name,
    NULL as specialty,
    avg_readmission_rate as readmission_rate_pct,
    avg_volume as total_encounters
FROM specialty_benchmarks;