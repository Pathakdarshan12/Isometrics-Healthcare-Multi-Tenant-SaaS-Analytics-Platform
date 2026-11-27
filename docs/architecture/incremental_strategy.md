# Materialization & Incremental Strategy

## What is materialized how

| Layer | Materialization | Why |
|---|---|---|
| staging | `view` (18 of 21 are `secure=true`) | Always current with raw; cheap. Secure views hide their definition and disable optimizations that could reveal filtered-out rows |
| intermediate | `ephemeral` | Business logic shared by marts without storing extra copies. Inlined as CTEs, so no RLS surface of their own |
| marts (aggregates) | `table` | Rebuilt each run; small (hospital × period grain) |
| marts (row-level, high volume) | `incremental` | See below |
| dimensions (hospitals, providers, facilities) | `snapshot` (SCD Type 2) | Keep history of attribute changes |

Defaults are set in `dbt_project.yml`; individual models override them in
`config()`.

## Incremental models

| Model | Strategy | `unique_key` | New-row filter |
|---|---|---|---|
| `fct_encounters` | `delete+insert` | `encounter_id` | `loaded_at_timestamp > max(loaded_at_timestamp)` in the target |
| `fct_billing_transactions` | `merge` | `transaction_id` | none (see below) |
| `fct_hipaa_audit_trail` | `append` | `audit_id` | `start_time > max(access_timestamp)`; first build loads 7 days |

All three use `on_schema_change='fail'` (set explicitly on encounters and billing;
the project default for the audit trail) and are clustered by `hospital_id` plus a
date column.

### `fct_encounters` — `delete+insert`

```sql
{% if is_incremental() %}
where loaded_at_timestamp > (
    select coalesce(max(loaded_at_timestamp), '1900-01-01'::timestamp_ntz)
    from {{ this }}
)
{% endif %}
```

- Encounters are mostly append-only, but a re-delivered encounter (coding
  correction, late discharge) gets a new `_loaded_at`. Its `encounter_id` row is
  then deleted and re-inserted.
- The filter is on *load* time, not admission date, so late-arriving history
  (backfills) is picked up by a normal incremental run. No full refresh is needed.
- `is_readmission` is computed in staging over the patient's full history, so
  recomputing a single encounter gives the same answer as a full rebuild. One
  exception: a backfilled *earlier* stay can turn an already-loaded later stay into
  a readmission. That later row isn't reloaded, so run
  `dbt run --select fct_encounters --full-refresh` after a historical backfill.

### `fct_billing_transactions` — `merge`

Payment status changes over time (Pending → Paid / Denied), so existing rows must
be updated in place, which is what `merge` on `transaction_id` does.

**Current limitation:** the model has no `is_incremental()` filter, so every
run merges the full transaction history. Results are correct, but the run does a
full rebuild's work. Fixing it means exposing a load timestamp from
`int_financial__revenue_cycle` (e.g. `loaded_at_timestamp`) and filtering on it
with a lookback for status updates. Because of `on_schema_change='fail'`, adding
the column needs a one-time `--full-refresh`.

### `fct_hipaa_audit_trail` — `append`

Audit events are immutable, so rows are only ever inserted. The source is
`SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY`, which lags by up to ~45 minutes. Each
run therefore picks up queries that became visible since the newest event already
stored.

## Choosing a strategy for a new model

```
Rows never change after they arrive?          → append
Rows change, and you can identify them by key:
    whole row is recomputed from source        → delete+insert
    only some columns change (status, amounts) → merge
Small aggregate (hospital × day/month)?       → table (simpler than incremental)
```

Always filter on a load/ingestion timestamp rather than a business date, so late
data is caught. Also make sure everything the model computes can be recomputed
from the rows the filter selects. If a value depends on other rows (window
functions, running totals), either compute it upstream over full history (as
readmissions are) or plan for a full refresh.

## Snapshots

```sql
{% snapshot snap_providers %}
{{ config(target_schema='snapshots', unique_key='provider_id',
          strategy='timestamp', updated_at='loaded_at_timestamp',
          invalidate_hard_deletes=True) }}
select ... from {{ ref('stg_healthcare__providers') }}
{% endsnapshot %}
```

`snap_hospitals` and `snap_facilities` follow the same pattern. Query current
state with `where dbt_valid_to is null`.

## Operations

```bash
dbt run --select fct_encounters                   # incremental
dbt run --select fct_encounters --full-refresh    # rebuild from scratch
dbt snapshot
```

Changing a model's strategy or columns requires `--full-refresh` (because of
`on_schema_change='fail'`). The RLS post-hook re-attaches the policy after any
rebuild (see [rls_implementation.md](rls_implementation.md)).

`analyses/incremental_strategy_benchmark.sql` can be compiled and run to compare
strategies on your own warehouse. This doc doesn't quote numbers that haven't
been measured.
