# Data Model

IsoMetrics is a multi-tenant warehouse: every hospital is a tenant identified by
`hospital_id`, and every tenant-scoped table carries that column so the
`hospital_isolation_policy` row access policy can filter it (see
[rls_implementation.md](rls_implementation.md)).

```
RAW_PHI.raw_*  (21 tables, loaded by scripts/load_data_to_snowflake.sql)
      │
      ▼
staging        stg_healthcare__* / stg_reference__*   views, secure, RLS attached
      │        de-identification, typing, cross-tenant FK validation, readmission flags
      ▼
intermediate   int_*                                   ephemeral (inlined as CTEs)
      │        joins, clinical scoring, enrichment
      ▼
marts          fct_*                                   tables / incremental, RLS attached
               aggregate KPIs per hospital and period
snapshots      snap_hospitals / snap_providers / snap_facilities   SCD Type 2
```

## Schema naming

The project uses dbt's default `generate_schema_name`, so a model's schema is
`<target schema>_<layer schema>`:

| Target (profile schema) | Staging | Marts | Snapshots |
|---|---|---|---|
| dev (`dbt_dev`) | `DBT_DEV_STAGING` | `DBT_DEV_MARTS` | `SNAPSHOTS` (`target_schema`) |
| ci (`dbt_ci_<run>`) | `DBT_CI_<run>_STAGING` | `DBT_CI_<run>_MARTS` | `SNAPSHOTS` |
| prod (`marts`, from `dbt_prod.yml`) | `MARTS_STAGING` | `MARTS_MARTS` | `SNAPSHOTS` |

Raw data always lives in `RAW_PHI`, in the database named by
`DBT_RAW_DATABASE` (defaults to the target database). CI sets it to
`ISOMETRICS_DEV` because CI's own `RAW_PHI` is dropped after every run.

> The runbooks refer to the marts schema as `MARTS`. Substitute the actual name for
> your target from the table above.

## Source tables (`RAW_PHI`)

| Domain | Tables |
|---|---|
| Tenant & administrative | `raw_hospitals`, `raw_patients` (PHI), `raw_providers`, `raw_facilities` |
| Encounters & clinical | `raw_encounters`, `raw_vital_signs`, `raw_clinical_orders`, `raw_clinical_results`, `raw_medication_administration`, `raw_patient_allergies`, `raw_problem_list` |
| Quality & care coordination | `raw_quality_measures`, `raw_care_plans`, `raw_referrals` |
| Financial | `raw_billing_transactions`, `raw_patient_coverage`, `raw_prior_authorizations` |
| Population health | `raw_sdoh_screenings` |
| Reference (not tenant-scoped) | `raw_diagnoses` (ICD-10), `raw_procedures` (CPT), `raw_payers` |

DDL: `scripts/isometrics_healthcare_snowflake_setup.sql`. Freshness: sources warn
after 4 hours and error after 6, on `_loaded_at`.

## Staging layer

One view per source. Staging is where the rules every downstream model relies on
are enforced:

- **De-identification (HIPAA Safe Harbor)** in `stg_healthcare__patients`:
  names and MRN are not selected; `date_of_birth` is reduced to `birth_year`
  (null for ages 90+); `age_years` is top-coded at 90; ZIP becomes a 3-digit
  prefix via `deidentify_zipcode`, with low-population prefixes set to `000`.
- **Tenant consistency** in `stg_healthcare__encounters`: an encounter is
  dropped if its patient, provider or facility belongs to a different
  hospital.
- **Readmissions** in `stg_healthcare__encounters`: an inpatient admission is a
  30-day readmission when the patient's most recent *inpatient* discharge at the
  same hospital was 1–30 days earlier. ED and outpatient visits in between don't
  reset it. `assert_readmission_logic_valid` recomputes this independently.
- **Basic validity**: discharge ≥ admission, non-negative charges and length of
  stay, non-null `hospital_id`.

Reference models (`stg_reference__*`) have no `hospital_id` and no RLS.

## Intermediate layer (ephemeral)

| Model | Purpose |
|---|---|
| `int_encounters__enriched` | Encounter + hospital, patient, provider, facility, diagnosis context |
| `int_patient__journey` | Patient risk category, 30-/7-day return flags |
| `int_clinical__vitals_enriched` | Vital trends, NEWS components, partial NEWS2 / qSOFA, deterioration flags |
| `int_clinical__orders_enriched` | Order lifecycle and turnaround timing |
| `int_clinical__lab_results_enriched` | Lab trends, critical values, panel categories |
| `int_clinical__medication_safety` | Allergy conflicts, high-risk verification, IV witness, late administration |
| `int_clinical__patient_profile` | 360° patient view and risk tier |
| `int_clinical__comorbidity_index` | Charlson Comorbidity Index per patient (with age adjustment) |
| `int_financial__revenue_cycle` | Billing + payer + encounter, A/R aging |
| `int_financial__prior_authorizations_enriched` | Authorizations + payer + linked claims, charges at risk |
| `int_quality__measure_results` | Abstracted CMS measure records with timing targets |
| `int_care_coordination__referrals_enriched` | Referrals with urgency SLAs and closed-loop status |

Because these are ephemeral, they don't exist in the warehouse and have no RLS of
their own. They're compiled into the marts that use them.

## Marts

| Mart | Grain | Materialization |
|---|---|---|
| **core** | | |
| `fct_encounters` | encounter | incremental, `delete+insert` |
| `fct_billing_transactions` | billing transaction | incremental, `merge` |
| **clinical** | | |
| `fct_clinical_quality_metrics` | hospital × day | table |
| `fct_early_warning_surveillance` | hospital × day | table |
| `fct_laboratory_quality_metrics` | hospital × day | table |
| `fct_medication_safety_metrics` | hospital × day | table |
| `fct_cms_core_measures_performance_dashboard` | hospital × measure × quarter (inferred from vitals/orders) | table |
| `fct_quality_measure_performance` | hospital × measure × quarter (from abstracted records) | table |
| `fct_population_health_dashboard` | hospital (current snapshot) | table |
| `fct_provider_performance` | provider | table |
| **financial** | | |
| `fct_financial_performance` | hospital × day | table |
| `fct_prior_authorization_metrics` | hospital × payer × month | table |
| **operational** | | |
| `fct_operational_metrics` | hospital × day | table |
| `fct_care_coordination_metrics` | hospital × month | table |
| **observability** | | |
| `fct_sla_monitoring` | hospital (current SLA status) | table |
| `fct_cost_attribution` | hospital × day | table |
| `fct_hipaa_audit_trail` | PHI access event | incremental, `append` |

Every mart has `hospital_id` and the RLS post-hook. The three newest marts
(`fct_quality_measure_performance`, `fct_prior_authorization_metrics`,
`fct_care_coordination_metrics`) also have a tenant-scoped surrogate key
(`tenant_surrogate_key`) and a `unique_combination_of_columns` test on their grain.

Observability marts read `SNOWFLAKE.ACCOUNT_USAGE`, so the building role needs
`IMPORTED PRIVILEGES` on the `SNOWFLAKE` database, and their contents lag by up to
~45 minutes (query history) or 2 hours (policy references).

## Snapshots (SCD Type 2)

`snap_hospitals`, `snap_providers` and `snap_facilities` use the `timestamp`
strategy on `loaded_at_timestamp` with `invalidate_hard_deletes`. Run with
`dbt snapshot`; prod runs them after deploying marts.

## Consumers

- **Streamlit dashboard** (`monitoring_dashboard/`): queries marts directly
  (currently hard-coded to `DBT_DEV_MARTS`).
- **Analytics API** (`api/`): exposes the aggregate marts listed in
  `api/datasets.py`. Row-level marts (`fct_encounters`,
  `fct_billing_transactions`, `fct_hipaa_audit_trail`) aren't exposed.
