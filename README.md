# 🏥 IsoMetrics Healthcare Analytics Platform

---

## **Project Vision**

IsoMetrics Healthcare is a multi-tenant healthcare analytics platform built on **Snowflake + dbt**, applying production data engineering practices to one of the most regulated industries: **healthcare analytics**. All data is synthetic.

It tackles the problems a real hospital analytics platform has to solve:

- **Multi-tenant data isolation** with Row-Level Security (RLS)
- **HIPAA audit trail** built from Snowflake query and access history
- **Scheduled pipeline** every 3 hours (generate → load → `dbt build`) with a 4-hour freshness SLA, monitored per hospital
- **Clinical quality analytics** (30-day readmission rates, mortality tracking, early warning scores)
- **Cost attribution** per hospital from Snowflake query history
- **Population health management** with SDOH screening integration
- **Medication safety tracking** with allergy conflict detection
- **CMS Core Measures** (SEP-1, AMI-8a, STK-4, HF-2, PN-6, readmissions)
- **Care coordination & prior authorization** analytics (referrals, care plans, payer approvals)

---

## **Architecture Overview**

```
┌─────────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │  Streamlit   │  │   FastAPI    │  │  dbt Docs /  │           │
│  │  Dashboard   │  │  (RLS-aware) │  │   Lineage    │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      MARTS LAYER (Gold)                         │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Clinical Quality │ Financial │ Operational │ Population │   │
│  │  ─────────────────────────────────────────────────────── │   │
│  │  • Readmissions   │ • Revenue │ • Bed Util  │ • SDOH     │   │
│  │  • Mortality      │ • A/R     │ • Staffing  │ • Risk     │   │
│  │  • Lab Quality    │ • Denials │ • Capacity  │ • Chronic  │   │
│  │  • Med Safety     │ • Cost    │ • Flow      │ • Care Mgmt│   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────────┐
│                 INTERMEDIATE LAYER (Silver)                     │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  • Encounters Enriched    • Patient Journey              │   │
│  │  • Revenue Cycle          • Clinical Orders Enriched     │   │
│  │  • Vitals Enriched        • Medication Safety            │   │
│  │  • Lab Results Enriched   • Patient Profile (360°)       │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────────┐
│                   STAGING LAYER (Bronze)                        │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  De-identification │ Data Quality │ Type Casting         │   │
│  │  PII Hashing       │ Validation   │ Standardization      │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              ▲
                              │
┌─────────────────────────────────────────────────────────────────┐
│                      RAW LAYER (PHI)                            │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  21 Source Tables  │  Row-Level Security  │  Audit Logs  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🚀 **What Makes This Project Exceptional**

### **1. Production-Grade Security Architecture**

Most data projects ignore security. **This one doesn't.**

#### **Row-Level Security (RLS) Implementation**
```sql
-- Excerpt of macros/setup_rls_policies.sql (rls_hospital_isolation_body)
CASE
  WHEN CURRENT_ROLE() LIKE 'HOSPITAL_%_ANALYST' AND CURRENT_ROLE() NOT LIKE '%_PHI_ANALYST' THEN
    hospital_id = REGEXP_REPLACE(CURRENT_ROLE(), 'HOSPITAL_(.*)_ANALYST', '\\1')
  WHEN CURRENT_ROLE() = 'HOSPITAL_ANALYST' THEN
    EXISTS (
      SELECT 1
      FROM (
        -- rename the column: an unqualified hospital_id inside a subquery binds
        -- to the table's own column (always true), not the policy argument
        SELECT hospital_id AS mapped_hospital_id, user_name, access_start_date, access_end_date
        FROM AUDIT.user_hospital_mapping
      ) m
      WHERE m.user_name = CURRENT_USER()
        AND m.mapped_hospital_id = hospital_id
        AND CURRENT_DATE() BETWEEN m.access_start_date AND m.access_end_date
    )
  ELSE FALSE   -- fail closed
END
```

Every tenant-scoped staging view and mart table gets the policy attached by a dbt post-hook (`apply_rls_policy`, idempotent and view/table-aware). `setup_rls_policies` creates the policies if missing and updates their body in place, so it's safe to run on every deploy. Isolation is verified, not assumed:
- `assert_rls_policy_applied` checks every staging/mart model has the policy attached (live `INFORMATION_SCHEMA.POLICY_REFERENCES`)
- `assert_no_cross_hospital_*` check joins never cross tenants
- `assert_no_role_filters_in_models` fails the build if a model filters on `CURRENT_ROLE()` instead of relying on the policy

All of these block CI and production deploys.

#### **HIPAA Audit Trail**
- **PHI access history** from Snowflake query history: user, role, timestamp, tables, rows, cost
- **Unauthorized access detection** (role not permitted for the data accessed)
- **Bulk access monitoring** to prevent data exfiltration
- **Query history analysis** for compliance reporting

---

### **2. Advanced Clinical Analytics**

This isn't just SELECT * FROM patients. These are **real clinical metrics** used by hospitals:

#### **National Early Warning Score (NEWS)**
```sql
-- Implemented from actual clinical guidelines
news_respiratory_score +
news_oxygen_score +
news_systolic_score +
news_heart_rate_score
```

#### **30-Day Readmission Calculation**
Uses **lag() window functions** to properly track inpatient-to-inpatient readmissions within 30 days. CMS-compliant methodology.

#### **Medication Safety Checks**
- Allergy conflict detection (before administration)
- High-risk medication verification tracking (barcode scanning)
- IV medication witness requirements
- Critical lab value notification compliance

#### **Population Health Risk Stratification**
- Chronic disease burden scoring
- Social Determinants of Health (SDOH) screening integration
- Care management candidacy identification
- Utilization pattern analysis (frequent ED users, etc.)

---

### **3. Financial Intelligence**

#### **Real-Time Cost Attribution**
```sql
-- Excerpt of fct_cost_attribution: attribute each query to a hospital
coalesce(
    regexp_substr(qh.query_text, 'hospital_id\\s*=\\s*[\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1),
    regexp_substr(qh.query_text, 'hospital_id\\s*IN\\s*\\([\'"]([A-Z0-9_]+)[\'"]', 1, 1, 'ie', 1),
    'UNATTRIBUTED'
) as hospital_id
-- then warehouse credits are allocated in proportion to each hospital's execution time
```

**Why this matters**: Multi-tenant platforms need cost allocation. This model extracts `hospital_id` from query predicates and allocates warehouse costs proportionally. Limitation: queries scoped only by a row access policy (no explicit `hospital_id` predicate) land in `UNATTRIBUTED`; a production version would tag queries with the tenant (e.g. `QUERY_TAG`) instead.

#### **Revenue Cycle Analytics**
- Days in A/R by payer
- Collection rate trending
- Denial pattern analysis
- Payment variance (expected vs actual reimbursement)

---

### **4. Sophisticated Data Quality Framework**

#### **320+ dbt Data Tests Across 3 Categories**

**Generic Tests** (Reusable):
- `no_cross_tenant_leakage`: Validates foreign keys stay within tenant boundaries
- `has_tenant_column`: Ensures RLS enforcement
- `no_phi_in_column`: Regex pattern matching for SSN/MRN/phone numbers

**Singular Tests** (Domain-Specific):
- `assert_no_medications_given_despite_allergies`: **CRITICAL SAFETY TEST**
- `assert_critical_lab_values_timely_response`: Ensures provider notification within 1-2 hours
- `assert_reasonable_readmission_rate`: Data quality check (1-15% expected range)
- `assert_high_risk_medications_verified`: Barcode scanning compliance for insulin, heparin, etc.

**Schema Tests**:
- Referential integrity across 21 source tables
- Accepted value constraints
- Range validations
- Uniqueness and nullability checks

---

### **5. Real Production Data Generation**

`data_generation/generate_data.py` is a vectorized, streaming generation engine (NumPy + PyArrow) for all 21 raw tables. It produced **3M encounters / 104M rows across 100 hospitals in about 5 minutes at under 500 MB of RAM** (measured; see [Data Generation](#data-generation--loading)):

```python
class HealthcareDataGenerator:
    """
    Generates statistically realistic healthcare data with:
    - Proper ICD-10/CPT coding
    - Clinical correlations (diagnosis → typical LOS → expected charges)
    - Temporal patterns (readmissions within 30 days)
    - Geographic distribution (US regions)
    - Payer mix (commercial, government, self-pay)
    """
```

**Key Features**:
- **Referential integrity preserved** across all 18 tables
- **No cross-hospital contamination** (patient_id never appears in multiple hospitals)
- **Realistic distributions**: Log-normal LOS, proper readmission rates, mortality rates
- **Medical code libraries**: 100+ ICD-10 codes, 50+ CPT codes, 40+ lab tests, 50+ medications
- **Clinical realism**: Allergies → medication conflicts, vitals → NEWS scores, diagnoses → severity levels

---

## **Data Model Deep Dive**

### **21 Source Tables Across 6 Domains**

#### **Core Clinical** (9 tables)
1. `raw_encounters` - Patient visits/admissions
2. `raw_vital_signs` - Temperature, BP, HR, SpO2, NEWS scoring
3. `raw_clinical_orders` - Labs, radiology, medications, procedures
4. `raw_clinical_results` - Lab values, imaging reports
5. `raw_medication_administration` - MAR with barcode verification
6. `raw_patient_allergies` - Drug/food allergies with severity
7. `raw_problem_list` - Active diagnoses beyond encounters
8. `raw_care_plans` - Nursing interventions
9. `raw_quality_measures` - CMS Core Measures tracking

#### **Financial** (3 tables)
10. `raw_billing_transactions` - Charges, payments, adjustments
11. `raw_patient_coverage` - Insurance policies, deductibles
12. `raw_prior_authorizations` - Pre-approval tracking

#### **Administrative** (3 tables)
13. `raw_hospitals` - Tenant master data
14. `raw_patients` - Demographics (PHI)
15. `raw_providers` - Physician roster

#### **Population Health** (2 tables)
16. `raw_sdoh_screenings` - Social determinants (housing, food, transportation)
17. `raw_referrals` - Care coordination

18. `raw_facilities` - Units/departments per hospital

#### **Reference Data** (3 tables)
19. `raw_diagnoses` - ICD-10 lookup
20. `raw_procedures` - CPT codes
21. `raw_payers` - Insurance plans

---

### **Intermediate Models (Business Logic Layer)**

These aren't just joins. They implement **complex healthcare algorithms**:

#### 1.`int_clinical__vitals_enriched`
```sql
-- Calculates NEWS score components
-- Identifies rapid deterioration (temp +2°F, HR +30, SBP -30)
-- Composite alerts: sepsis (hypotension + tachycardia + hypoxia)
-- Trend analysis via lag() functions
```

#### 2.`int_patient__journey`
```sql
-- Readmission logic with 30-day windows
-- Patient risk stratification (chronic disease count + utilization)
-- 7-day ED return tracking
-- Lifetime encounter summary
```

#### 3.`int_clinical__medication_safety`
```sql
-- Allergy conflict detection (fuzzy name matching)
-- High-risk medication flagging
-- IV witness verification
-- Late administration tracking
-- Adverse reaction monitoring
```

#### 4.`int_clinical__comorbidity_index`
```sql
-- Charlson Comorbidity Index (Quan 2005 ICD-10 mapping, Charlson 1987 weights)
-- Severity hierarchy: severe form supersedes mild (diabetes, liver, cancer)
-- Age-adjusted CCI (+1 per decade from 50)
```

#### 5.`int_quality__measure_results` / `int_care_coordination__referrals_enriched` / `int_financial__prior_authorizations_enriched`
```sql
-- Abstracted CMS measure records with timing targets (SEP-1 60m, AMI-8a 90m, STK-4 60m)
-- Referral scheduling SLAs by urgency + closed-loop status
-- Prior auths linked to claims: charges at risk, "prior authorization not obtained" denials
```

#### 6.`int_clinical__patient_profile`
```sql
-- 360° patient view aggregating:
--   • Active problems + chronic disease count
--   • Life-threatening allergies
--   • Recent vitals + latest NEWS score
--   • SDOH risk factors
--   • Insurance coverage + financial burden
--   • Medication adherence (refusal rate)
--   • Utilization patterns (ED visits, admissions)
-- Risk scoring: Very High / High / Medium / Low
```

---

### **Mart Models (Analytics Layer)**

#### **Clinical Quality Dashboards**

**1.`fct_clinical_quality_metrics`**
- Daily 30-day readmission rate (CMS methodology)
- Mortality rate trending
- Average LOS by hospital type
- High-risk patient counts

**2.`fct_medication_safety_metrics`**
- Barcode scanning compliance (target: >90%)
- Allergy violation tracking (target: ZERO)
- High-risk medication verification rate
- Adverse reaction rates
- Overall medication safety score (0-100)

**3.`fct_early_warning_surveillance`**
- NEWS score distribution (High/Medium/Low risk)
- Sepsis alerts (hypotension + tachycardia + hypoxia)
- Rapid deterioration events
- Respiratory distress alerts
- Pain management metrics

**4.`fct_laboratory_quality_metrics`**
- Turnaround time (median, p95)
- STAT lab performance (<1 hour target)
- Critical value counts
- Results within target timeframes (2hr, 4hr, 24hr)
- Lab quality score (0-100)

**5.`fct_population_health_dashboard`**
- Total population snapshot
- Chronic disease prevalence
- High-risk patient prevalence
- SDOH risk factors (housing, food, transportation)
- Care management candidates
- Medication non-adherence rates
- Population health score (0-100)

**6.`fct_cms_core_measures_performance_dashboard`**
- SEP-1 (Sepsis bundle compliance)
- AMI-2 (Aspirin at arrival)
- READM-30 (30-day readmissions)
- Quarterly performance vs CMS targets
- Gap analysis

#### **Financial Analytics**

**7.`fct_financial_performance`**
- Daily revenue cycle metrics
- Net collection rate
- Denial rate
- Days in A/R (median, average)
- AR aging (>30, >60, >90 days)
- Payer mix analysis

**8.`fct_billing_transactions`** (Incremental)
- Transaction-level detail with MERGE strategy
- Payment variance analysis
- Denial reason tracking

#### **Operational Metrics**

**9.`fct_operational_metrics`**
- Bed occupancy rate (target: 75-85%)
- Daily admissions/ED visits
- Patient flow patterns
- Provider productivity
- Weekend vs weekday patterns

**`fct_quality_measure_performance`**
- Quarterly CMS measure performance from chart abstraction (numerator / eligible denominator)
- Median and p90 time-to-treatment vs target
- Case-mix context: cohort mortality, average Charlson index

**`fct_care_coordination_metrics`**
- Referral completion, closed-loop and scheduling-within-SLA rates
- Care plans active / overdue for evaluation / goal completion

**`fct_prior_authorization_metrics`**
- Approval and denial rates by payer, decision turnaround
- Charges at risk from denied/pending authorizations

#### **Observability**

**10.`fct_sla_monitoring`**
- Data freshness (<4 hours target)
- Data quality score (>99% target)
- Test failure tracking
- Row count anomalies

**11.`fct_cost_attribution`**
- Query-level cost tracking
- Cost per hospital
- Week-over-week cost trends
- Warehouse vs cloud services breakdown

**12.`fct_hipaa_audit_trail`** (Incremental)
- Every PHI access logged
- Unauthorized access detection
- Bulk access alerts
- Query cost attribution

---

##  **Technical Implementation Highlights**

### **Incremental Materialization Strategies**

**Delete+Insert** (`fct_encounters`)
```sql
-- Why: Encounters are mostly append-only
-- Partitioned by hospital_id + admission_date
-- Efficient micro-partition pruning
```

**Merge** (`fct_billing_transactions`)
```sql
-- Why: Payment status changes (Pending → Paid)
-- UPDATE existing + INSERT new in single operation
-- Clustered by hospital_id + transaction_date
```

**Append** (`fct_hipaa_audit_trail`)
```sql
-- Why: Audit logs are immutable
-- No updates, only inserts
-- Partitioned by access_timestamp
```

### **Performance Optimizations**

1. **Clustering Keys**: All large tables clustered by `hospital_id` + date dimension
2. **Ephemeral Intermediate Models**: No materialization overhead for transformation logic
3. **Secure Views**: Staging models use `secure=true` to prevent result caching (HIPAA requirement)
4. **Incremental Strategy Selection**: Analyzed query patterns to choose optimal strategy per model

### **dbt Macros (Healthcare-Specific)**

#### Clinical Scoring Algorithms
```jinja
{% macro calculate_cha2ds2_vasc_score(...) %}
  -- Atrial fibrillation stroke risk (0-9 points)
{% endmacro %}

{% macro calculate_hasbled_score(...) %}
  -- Bleeding risk on anticoagulation (0-9 points)
{% endmacro %}

{% macro calculate_apache_ii_score(...) %}
  -- ICU mortality prediction (0-71 points)
{% endmacro %}

{% macro calculate_sofa_score(...) %}
  -- Sepsis organ dysfunction (0-24 points)
{% endmacro %}

{% macro calculate_mews_score(...) %}
  -- Early warning score for deterioration
{% endmacro %}

{% macro calculate_news2_score(...) %}
  -- National Early Warning Score 2 (RCP 2017), 0-20 points
{% endmacro %}

{% macro calculate_qsofa_score(...) %}
  -- quick SOFA sepsis screen (Sepsis-3), 0-3 points
{% endmacro %}

{% macro charlson_condition(icd10) %} / {% macro charlson_weight(condition) %}
  -- Charlson Comorbidity Index (Quan 2005 ICD-10 mapping)
{% endmacro %}
```

These implement **actual clinical guidelines** from medical literature.

#### Utility Macros
```jinja
{% macro calculate_patient_age(dob, ref_date) %}
{% macro calculate_age_group(age) %}
{% macro calculate_length_of_stay(admit, discharge) %}   -- CMS midnight convention
{% macro calculate_ar_aging_bucket(days) %}
{% macro safe_divide(num, den) %} / {% macro calculate_percentage(num, den) %}
{% macro tenant_surrogate_key(cols) %}                     -- hospital_id-scoped keys
{% macro calculate_readmission_rate(readmit_col, type_col) %}
{% macro deidentify_zipcode(zip_col) %}  -- HIPAA Safe Harbor
{% macro apply_rls_policy() %}           -- Post-hook automation
```

---

## **Monitoring Dashboard (Streamlit)**

`monitoring_dashboard/` is a Streamlit application (~2,800 lines): `app.py` has the five views below, and `pages/` adds Clinical Quality, Financial Performance and SLA Monitoring pages:

### **Main Dashboard**
- Real-time SLA compliance gauges
- Data quality scores
- Freshness monitoring
- Clinical quality trends
- Cost attribution charts

### **HIPAA Audit Trail**
- PHI access timeline
- Unauthorized access alerts
- Bulk access detection
- User access patterns
- Query detail drill-down

### **Data Lineage**
- Model refresh status
- Freshness vs size scatter plots
- Stale model alerts (>24 hours)

### **Hospital Comparison**
- Multi-select hospital benchmarking
- Performance scorecards with gradient coloring
- Readmission rate comparison
- Cost efficiency ranking
- Hospital type/EMR distribution

### **Alerts**
- Critical/Warning/Info classification
- SLA breach notifications
- Clinical quality alerts (high readmission rate, etc.)
- Operational alerts (bed occupancy >95%)

---

## **Scheduled Pipeline**

`orchestration/isometrics_orchestration.py` runs one end-to-end batch, and `.github/workflows/pipeline_schedule.yml` runs it **every 3 hours** against production. A 3-hour cadence keeps every transactional source inside the 4-hour freshness warning (`dbt source freshness`, error at 6 hours), with slack for scheduler delays.

Each run:
1. Takes the 3-hour window ending at the current UTC hour
2. Skips generate/load if that window is already in `RAW_PHI` (safe to retry)
3. Generates the window's encounters plus billing, vitals, orders, results, medication administration, quality measures, care plans, referrals and prior authorizations for the tenants already in Snowflake (`data_generation/daily_data_generation.py`). IDs embed the batch tag and generation is deterministic per window, so batches never collide and reruns reproduce the same files.
4. Uploads to `@RAW_PHI.HEALTHCARE_DATA_STAGE/batches/<tag>/` and `COPY`s into the raw tables (columns and casts derived from the raw DDL)
5. Runs `setup_rls_policies` → `dbt source freshness` → `dbt build` (models, all tests, snapshots)
6. Records the run in `AUDIT.PIPELINE_RUN_LOG` (window, rows loaded per table, status, duration, error)

```bash
python -m orchestration.isometrics_orchestration --target dev               # one run against dev
python -m orchestration.isometrics_orchestration --target dev --skip-dbt    # load only
python -m orchestration.isometrics_orchestration --target dev --dbt-only    # transform only
python -m pytest orchestration/tests                                        # offline tests
```

The schedule is **off until** the repository variable `PIPELINE_ENABLED` is set to `true`. Manual runs (`workflow_dispatch`) always work. The first run needs the master data (hospitals, patients, providers, facilities, payers) already loaded via the Quick Start. Pipeline runs and production deploys share a concurrency group, so they never overlap.

---

## **Analytics API (FastAPI)**

`api/` is a read-only REST API over the aggregate marts.

- **Tenant isolation is enforced by Snowflake, not the API.** Each API key is bound to one Snowflake role (e.g. `HOSPITAL_HOSP_0001_ANALYST`); every request runs `USE ROLE` for that role (secondary roles disabled), so the row access policy decides which rows come back.
- **Whitelisted datasets only**, all user input bound as query parameters. Row-level marts (encounters, billing, audit trail) are not exposed.
- API keys are stored only as SHA-256 digests.

```bash
pip install -r api/requirements.txt

# create a key bound to a role (the API's Snowflake user must be granted that role)
python -m api.keys hosp-0001-dashboard HOSPITAL_HOSP_0001_ANALYST
# -> add the printed JSON entry to ISOMETRICS_API_KEYS in .env

uvicorn api.main:app --reload            # docs at http://localhost:8000/docs
curl -H "X-API-Key: <key>" "http://localhost:8000/v1/datasets/clinical-quality?start_date=2025-01-01&limit=50"

python -m pytest api/tests               # offline tests, no Snowflake needed
```

| Endpoint | Description |
|---|---|
| `GET /health` | Liveness (no auth) |
| `GET /v1/me` | The client and Snowflake role bound to your key |
| `GET /v1/datasets` | Available datasets |
| `GET /v1/datasets/{name}` | Rows from a mart; `hospital_id`, `start_date`, `end_date`, `limit` (≤1000), `offset` |

Datasets: `clinical-quality`, `core-measures`, `early-warning`, `laboratory-quality`, `medication-safety`, `financial-performance`, `prior-authorizations`, `operational`, `care-coordination`, `cost-attribution`.

Configuration (`.env`): `SNOWFLAKE_ACCOUNT/USER/PASSWORD/WAREHOUSE/DATABASE`, `ISOMETRICS_MARTS_SCHEMA` (default `DBT_DEV_MARTS`), `ISOMETRICS_API_KEYS`.

---

## **Development Workflow**

### **Local Development**
```bash
# Setup Python environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate
pip install -r requirements.txt

# Configure dbt profile (see Quick Start below for the profiles.yml template)

# Install dbt packages
cd isometrics_healthcare
dbt deps

# Run models
dbt run --select staging      # Bronze layer
dbt run --select intermediate # Silver layer
dbt run --select marts        # Gold layer

# Run tests
dbt test                                   # all tests
dbt test --select assert_no_cross_hospital_encounters   # a single test
dbt test --select stg_healthcare__encounters            # all tests on one model

# Generate documentation
dbt docs generate
dbt docs serve
```

### **CI/CD Pipeline** (GitHub Actions)

`.github/workflows/dbt_ci.yml` implements:

1. **Environment Setup**: Creates ephemeral CI schema per PR
2. **RLS Policy Creation**: Runs `setup_rls_policies` macro
3. **Sequential Execution**: Staging → Intermediate → Marts
4. **Data Quality Tests**: Runs all dbt tests
5. **RLS Validation**: Verifies policies are applied
6. **Documentation Generation**: Creates artifact with manifest.json
7. **Cleanup**: Drops CI schema after run

All test steps are blocking. `.github/workflows/dbt_prod.yml` deploys to `ISOMETRICS_PROD` only after CI passes on `main` (exact tested commit), then runs snapshots, post-deploy tests and RLS verification. `.github/workflows/api_ci.yml` runs the API test suite.

**Key Innovation**: Each PR gets isolated test environment with full RLS policies.

---

## **Data Generation & Loading**

### **Generate Synthetic Data**
```bash
# run from the repo root; writes data_generation/parquet/<table>.parquet + generation_report.json
python data_generation/generate_data.py                               # 100 hospitals, 30 days
python data_generation/generate_data.py --target-encounters 3000000   # sizes the date range (~236 days)
python data_generation/generate_data.py --hospitals 10 --days 7 --format both   # Parquet + CSV
python -m pytest data_generation/tests                                # integrity tests
```

**Design:**
- **Vectorized:** fields are drawn as NumPy arrays; variable child counts (vitals per encounter, orders per encounter, administrations per order) expand with `np.repeat`, not Python loops.
- **Streaming:** patients and encounters are generated in batches. Each batch's dependent tables are written immediately (PyArrow `ParquetWriter`, optional CSV append) and released. `--batch-size` caps the rows per batch *including* child tables, and encounters per batch adapt to the measured fan-out, so memory stays flat as volume grows.
- **Tenant-consistent:** every patient, provider and facility reference is sampled from the row's own hospital.
- **Reproducible:** one `--seed` reproduces the dataset.
- **Schema-exact:** output is conformed to the raw DDL (`data_generation/schema.py`), and the writer fails on schema drift.

**Measured** (100 hospitals, `--target-encounters 3000000`, default batch size, Parquet):

| | |
|---|---|
| Encounters | 3,011,896 over 236 days |
| Total rows (21 tables) | 103.9M, including 41.9M medication administrations, 25.4M orders, 13.2M vitals, 10.1M results, 1.23M patients |
| Wall time | 5 min 3 s (~343k rows/s end to end) |
| Peak RAM | 462 MB |
| Output | 3.8 GB Parquet |
| Integrity | 0 cross-tenant references, 0 orphaned child rows, 6.3% inpatient 30-day readmission rate |

At the same small configuration (10 hospitals, 7 days, ~0.97M rows), the previous row-by-row generator took 149 s at 814 MB; this engine takes about 4 s at 274 MB.

Clinical, financial, quality, care-coordination and prior-authorization tables are derived from the encounters, so diagnoses, timings and outcomes correlate (e.g. sepsis encounters get SEP-1 measure records, AMI encounters get door-to-balloon times).

### **Load to Snowflake**

```bash
# Upload the generated Parquet to the stage (@RAW_PHI.HEALTHCARE_DATA_STAGE/2023/), creds from .env
python -m utils.upload_files_to_stage

# Load all 21 raw tables
snowsql -f scripts/load_data_to_snowflake.sql
```

**Alternative**: Metadata-driven ingestion via `scripts/metadata_driven_stage_to_raw.sql` (stored procedures with configuration tables).

---

## **What I Have Learn From This Project**

### **Data Engineering**
- Multi-tenant architecture patterns
- Incremental processing strategies (delete+insert, merge, append)
- Partition and clustering optimization
- Star schema design for analytics
- Data quality frameworks
- Metadata-driven ingestion

### **Healthcare Analytics**
- Clinical quality metrics (30-day readmissions, mortality, LOS)
- Early warning score calculations (NEWS, MEWS)
- Risk stratification methodologies
- Population health analytics
- SDOH screening integration
- CMS Core Measures compliance

### **Security & Compliance**
- Row-Level Security (RLS) implementation
- HIPAA audit trail design
- PHI de-identification techniques
- Access control matrices
- Compliance monitoring

### **DevOps & DataOps**
- CI/CD for data pipelines
- dbt testing strategies
- Version control for analytics code
- Environment promotion (dev → CI → prod)
- Automated documentation generation

### **Business Intelligence**
- KPI dashboard design
- Real-time monitoring
- Alerting and anomaly detection
- Multi-tenant benchmarking
- Cost attribution and chargeback

---

## **Project Statistics**

| Metric | Count         |
|--------|---------------|
| **dbt Models** | 50 (21 staging, 12 intermediate, 17 marts) |
| **dbt Data Tests** | 320+          |
| **SQL Lines of Code** | ~12,000       |
| **Python Lines of Code** | ~6,000        |
| **Source Tables** | 21            |
| **Custom Macros** | 30+           |
| **Snapshots** | 3 (SCD Type 2)    |
| **Clinical Algorithms** | 8 (APACHE II, SOFA, qSOFA, MEWS, NEWS2, CHA₂DS₂-VASc, HAS-BLED, Charlson) |
| **Synthetic Data Generator** | Vectorized streaming engine: 3M encounters / 104M rows in ~5 min, <500 MB RAM |
| **Monitoring Dashboard** | ~2,800 lines  |
| **Analytics API** | FastAPI, 10 datasets, offline test suite |
| **Scheduled Pipeline** | every 3 hours, 10 transactional feeds, 4-hour freshness SLA |
| **Documentation** | 10,000+ words |

---

## **Quick Start Guide**

### **Prerequisites**
- Snowflake account (trial works)
- Python 3.11+
- dbt-core 1.11.0
- Git

### **Installation** (5 minutes)

```bash
# 1. Clone repository
git clone https://github.com/yourusername/isometrics-healthcare.git
cd isometrics-healthcare

# 2. Setup Snowflake
snowsql -f scripts/isometrics_healthcare_snowflake_setup.sql

# 3. Configure dbt
mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml <<EOF
isometrics_healthcare:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: YOUR_ACCOUNT
      user: DBT_USER
      password: YOUR_PASSWORD
      role: DBT_DEV_ROLE
      database: ISOMETRICS_DEV
      warehouse: DBT_DEV_WH
      schema: DBT_DEV_STAGING
      threads: 4
EOF

# 4. Python environment + credentials
python -m venv venv && source venv/bin/activate   # Windows: venv\Scripts\activate
pip install -r requirements.txt
cat > .env <<EOF
SNOWFLAKE_ACCOUNT=YOUR_ACCOUNT
SNOWFLAKE_USER=DBT_USER
SNOWFLAKE_PASSWORD=YOUR_PASSWORD
SNOWFLAKE_ROLE=DBT_DEV_ROLE
SNOWFLAKE_WAREHOUSE=DBT_DEV_WH
SNOWFLAKE_DATABASE=ISOMETRICS_DEV
SNOWFLAKE_SCHEMA=RAW_PHI
EOF

# 5. Generate and load data (from the repo root)
python data_generation/generate_data.py          # Parquet -> data_generation/parquet/
python -m utils.upload_files_to_stage
snowsql -f scripts/load_data_to_snowflake.sql

# 6. Run dbt
cd isometrics_healthcare
dbt deps
dbt run-operation setup_rls_policies
dbt run
dbt test
cd ..

# 7. Launch monitoring dashboard / API
streamlit run monitoring_dashboard/app.py
uvicorn api.main:app --reload
```

---

## **Documentation**

Architecture:
- [Data model](docs/architecture/data_model.md): layers, source tables, marts and their grains, schema naming
- [Row-level security](docs/architecture/rls_implementation.md): policies, the `apply_rls_policy` hook, verification tests
- [Materialization & incremental strategy](docs/architecture/incremental_strategy.md)
- [Ingestion](docs/architecture/metadata_driven_ingestion.md): COPY load path and the metadata-driven procedures

Runbooks: [tenant onboarding](docs/runbooks/%20tenant_onboarding.md) · [tenant offboarding](docs/runbooks/tenant_offboarding.md) · [backfill](docs/runbooks/backfill_tenant.md) · [incident response](docs/runbooks/incident_response.md)

- **dbt Docs**: Run `dbt docs generate && dbt docs serve`
- **Model Lineage**: Interactive DAG visualization
- **Column-Level Descriptions**: Every column documented
- **Test Descriptions**: What each test validates
- **Macro Docs**: Clinical algorithm references

---

##  **License**

MIT License - Use freely for learning, portfolios, or commercial projects.

---

## **Use Cases**

This project can be adapted for:

- **Portfolio Projects**: Demonstrate advanced data engineering skills
- **Learning dbt**: Real-world complexity beyond Jaffle Shop
- **Healthcare Startups**: Foundation for analytics platform
- **Consulting Engagements**: Proof-of-concept for hospital analytics
- **Education**: Teaching healthcare data warehousing
- **Certification Prep**: dbt Analytics Engineering certification

---

##  **Connect**

Questions? Want to discuss implementation details? Open an issue or reach out:

- **Email**: pathak12darshan@gmail.com
- **LinkedIn**: https://www.linkedin.com/in/pathakdarshan12/
- **Portfolio**: https://pathakdarshan12.github.io/portfolio/
---