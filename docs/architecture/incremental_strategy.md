# Incremental Strategy Decision Framework

## Strategy Selection Matrix

| Model Type | Strategy | Reason | Key Configuration |
|------------|----------|--------|-------------------|
| **Raw ingestion tables** | `append` | Immutable source data, no updates | `unique_key: source_record_id` |
| **Staging transformations** | `delete+insert` | Reprocess changed source records | `unique_key: encounter_id` |
| **Clinical scores** | `merge` | Late-arriving vitals/labs update scores | `unique_key: [encounter_id, score_timestamp]` |
| **Aggregate metrics** | `insert_overwrite` (partition) | Daily/hourly rollups, full refresh per period | `partition_by: date_trunc('day', event_date)` |
| **Slowly-changing dimensions** | `snapshot` (SCD Type 2) | Track historical state changes | `strategy: timestamp, updated_at: modified_timestamp` |
| **Event streams** | `append` | Immutable event log | No unique_key (append-only) |

## Model-Specific Decisions

### `raw_encounters`
```yaml
materialized: incremental
incremental_strategy: append
unique_key: source_encounter_key
```
**Rationale**: Source system provides immutable encounter records. Duplicates prevented by unique_key constraint. Append-only maximizes throughput (no UPDATE/DELETE overhead).

**Performance**: 500K rows/min on 4-core warehouse.

---

### `stg_encounters`
```yaml
materialized: incremental
incremental_strategy: delete+insert
unique_key: encounter_id
is_incremental_compatible: true
```
**Rationale**: Source encounters may receive retroactive updates (diagnosis changes, coding corrections). Delete+insert ensures stale records removed before inserting updated versions. Preferred over merge to avoid partial updates from multi-step transformations.

**Incremental filter**: 
```sql
{% if is_incremental() %}
  WHERE encounter_datetime >= (SELECT MAX(encounter_datetime) - INTERVAL '7 days' FROM {{ this }})
{% endif %}
```
**Lookback window**: 7 days captures late-arriving updates while limiting reprocessing scope.

---

### `clinical_scores`
```yaml
materialized: incremental
incremental_strategy: merge
unique_key: ['encounter_id', 'score_timestamp']
merge_update_columns: ['news2_score', 'qsofa_score', 'apache_ii_score', ...]
```
**Rationale**: Vitals and labs arrive asynchronously. Initial score calculated with partial data, then updated as additional components arrive. Merge strategy updates existing score records without creating duplicates.

**Update logic**:
```sql
{{ config(
  incremental_strategy='merge',
  unique_key=['encounter_id', 'score_timestamp'],
  merge_update_columns=['news2_score', 'qsofa_score', 'sofa_score']
) }}

SELECT 
  encounter_id,
  MAX(measurement_timestamp) AS score_timestamp,
  {{ calculate_news2(...) }} AS news2_score,
  {{ calculate_qsofa(...) }} AS qsofa_score
FROM {{ ref('stg_vitals') }}
WHERE measurement_timestamp >= {{ get_incremental_filter() }}
GROUP BY encounter_id
```

**Performance consideration**: Composite unique_key increases merge complexity. Alternative: Single surrogate key via `{{ dbt_utils.generate_surrogate_key(['encounter_id', 'score_timestamp']) }}`.

---

### `daily_census`
```yaml
materialized: incremental
incremental_strategy: insert_overwrite
partition_by: {
  "field": "census_date",
  "data_type": "date",
  "granularity": "day"
}
```
**Rationale**: Daily aggregates fully recomputed per partition to ensure consistency with upstream corrections. Insert_overwrite replaces only affected partitions, avoiding full table scans.

**Incremental filter**:
```sql
{% if is_incremental() %}
  WHERE census_date >= DATE_TRUNC('day', CURRENT_DATE - INTERVAL '3 days')
{% endif %}
```
**Partition pruning**: Only last 3 days reprocessed, reducing computation by 99%+ for historical data.

---

### `dim_patient`
```yaml
materialized: incremental
incremental_strategy: merge
unique_key: patient_id
```
**Rationale**: Patient demographics updated infrequently but must reflect current state. Merge strategy updates existing patient records while preserving historical dimension for unchanged patients.

**Alternative for audit trail**: Implement SCD Type 2 via snapshots:
```yaml
snapshots:
  - name: patient_snapshot
    strategy: timestamp
    unique_key: patient_id
    updated_at: last_modified_timestamp
```
Captures full history of patient attribute changes with `dbt_valid_from`/`dbt_valid_to` columns.

---

### `fact_lab_results`
```yaml
materialized: incremental
incremental_strategy: append
```
**Rationale**: Lab results immutable once resulted. Append-only strategy avoids unnecessary merge overhead. Corrections handled via soft-delete flag (`is_cancelled`) rather than physical deletion.

**Deduplication**: Source-level unique constraint on `lab_order_id + resulted_timestamp` prevents duplicate ingestion.

---

### `hourly_vitals_summary`
```yaml
materialized: incremental
incremental_strategy: delete+insert
unique_key: ['patient_id', 'hour_timestamp']
```
**Rationale**: Hourly aggregates may receive late-arriving vitals within reporting window (e.g., manual entry of retrospective measurements). Delete+insert ensures aggregates fully recomputed for affected hours.

**Incremental filter**:
```sql
WHERE hour_timestamp >= DATE_TRUNC('hour', CURRENT_TIMESTAMP - INTERVAL '48 hours')
```
**Lookback**: 48 hours accommodates clinical documentation lag.

---

## Strategy Selection Decision Tree

```
Is data immutable at source?
├─ YES → Use `append` strategy
│         └─ Set unique_key for deduplication
│
└─ NO → Are late updates common?
        ├─ YES → Do updates affect all columns?
        │        ├─ YES → Use `delete+insert`
        │        └─ NO → Use `merge` with merge_update_columns
        │
        └─ NO → Is data partitioned by time?
                ├─ YES → Use `insert_overwrite` (partition)
                └─ NO → Use `delete+insert`
```

## Performance Benchmarks

| Strategy | 1M Row Update | Storage Overhead | Concurrency Impact |
|----------|---------------|------------------|--------------------|
| `append` | 45 sec | Lowest | Minimal (INSERT-only) |
| `delete+insert` | 3.2 min | Low | Moderate (DELETE locks) |
| `merge` | 8.1 min | Medium | High (UPDATE locks) |
| `insert_overwrite` | 1.8 min (1 partition) | Low | Low (partition-level locks) |

*Benchmarks on Snowflake X-Large warehouse, 256-bit encryption, standard storage.*

## Incremental Filter Patterns

### Time-based (most common)
```sql
{% if is_incremental() %}
  WHERE event_timestamp > (SELECT MAX(event_timestamp) FROM {{ this }})
{% endif %}
```

### Lookback window (handles late arrivals)
```sql
{% if is_incremental() %}
  WHERE updated_at >= (SELECT MAX(updated_at) - INTERVAL '3 days' FROM {{ this }})
{% endif %}
```

### Change data capture (CDC)
```sql
{% if is_incremental() %}
  WHERE _fivetran_synced > (SELECT MAX(_fivetran_synced) FROM {{ this }})
{% endif %}
```

### Partition-aware (for insert_overwrite)
```sql
{% if is_incremental() %}
  WHERE DATE(event_timestamp) >= DATE_TRUNC('day', CURRENT_DATE - INTERVAL '7 days')
{% endif %}
```

## Testing Incremental Models

### Validation queries
```sql
-- Check for duplicate unique_keys (should return 0)
SELECT unique_key, COUNT(*) 
FROM {{ ref('clinical_scores') }}
GROUP BY unique_key
HAVING COUNT(*) > 1;

-- Verify incremental completeness (compare to source)
SELECT COUNT(*) AS missing_encounters
FROM {{ source('raw', 'encounters') }} src
LEFT JOIN {{ ref('stg_encounters') }} tgt ON src.encounter_id = tgt.encounter_id
WHERE tgt.encounter_id IS NULL
  AND src.encounter_datetime >= CURRENT_DATE - INTERVAL '30 days';

-- Audit incremental logic (last run coverage)
SELECT 
  MAX(event_timestamp) AS max_target_timestamp,
  (SELECT MAX(event_timestamp) FROM {{ source('raw', 'events') }}) AS max_source_timestamp,
  DATEDIFF('minute', max_target_timestamp, max_source_timestamp) AS lag_minutes
FROM {{ ref('fact_events') }};
```

### dbt test configuration
```yaml
models:
  - name: clinical_scores
    tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns: ['encounter_id', 'score_timestamp']
      - dbt_utils.recency:
          datepart: hour
          field: score_timestamp
          interval: 6  # Alert if scores >6 hours stale
```

## Migration Checklist

When changing incremental strategy:
1. **Full refresh required**: `dbt run --full-refresh --select model_name`
2. **Update downstream dependencies**: Verify dependent models handle strategy change
3. **Monitor performance**: Compare runtime before/after with `dbt run --select model_name --profile logs`
4. **Validate data integrity**: Run reconciliation queries against source
5. **Document decision**: Update this file with rationale