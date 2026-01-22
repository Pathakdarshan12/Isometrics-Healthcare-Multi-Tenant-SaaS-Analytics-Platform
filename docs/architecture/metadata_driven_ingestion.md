# Metadata-Driven Ingestion Configuration

## Architecture
Ingestion controlled via `config.metadata_registry` table, eliminating hard-coded table/column mappings.

## Metadata Registry Schema
```sql
CREATE TABLE config.metadata_registry (
  source_system VARCHAR(50),
  source_table VARCHAR(100),
  source_column VARCHAR(100),
  target_schema VARCHAR(50),
  target_table VARCHAR(100),
  target_column VARCHAR(100),
  data_type VARCHAR(50),
  transformation_rule TEXT,
  is_active BOOLEAN DEFAULT true,
  PRIMARY KEY (source_system, source_table, source_column)
);
```

## Configuration Process

### 1. Register Source System
```sql
INSERT INTO config.metadata_registry VALUES
  ('epic', 'PAT', 'PAT_ID', 'raw', 'patients', 'patient_id', 'VARCHAR(50)', NULL, true),
  ('epic', 'PAT', 'PAT_NAME', 'raw', 'patients', 'patient_name', 'VARCHAR(200)', 'UPPER(source_value)', true),
  ('epic', 'ENCOUNTERS', 'ENC_DATE', 'raw', 'encounters', 'encounter_datetime', 'TIMESTAMP', 'TO_TIMESTAMP(source_value, ''YYYY-MM-DD HH24:MI:SS'')', true);
```

### 2. Define Transformation Rules
Supported transformations in `transformation_rule` column:
- **Direct mapping**: `NULL` (1:1 copy)
- **Type casting**: `CAST(source_value AS INTEGER)`
- **Date parsing**: `TO_DATE(source_value, 'MM/DD/YYYY')`
- **String manipulation**: `TRIM(UPPER(source_value))`
- **Conditional logic**: `CASE WHEN source_value = 'Y' THEN true ELSE false END`
- **Lookups**: `(SELECT code FROM ref.icd10_map WHERE legacy_code = source_value)`

### 3. Ingestion Execution
Python orchestrator reads metadata and generates dynamic SQL:
```python
def build_ingestion_sql(source_system, source_table):
    metadata = query(f"""
        SELECT source_column, target_column, transformation_rule
        FROM config.metadata_registry
        WHERE source_system = '{source_system}'
          AND source_table = '{source_table}'
          AND is_active = true
    """)
    
    select_clause = ",\n".join([
        f"{row['transformation_rule'] or row['source_column']} AS {row['target_column']}"
        for row in metadata
    ])
    
    return f"""
        INSERT INTO raw.{metadata[0]['target_table']}
        SELECT {select_clause}
        FROM {source_system}.{source_table}
    """
```

## Adding New Data Sources

### Step 1: Source Profiling
```sql
-- Analyze source table structure
SELECT column_name, data_type, count_distinct, null_percentage
FROM source_system.information_schema.columns
WHERE table_name = 'NEW_TABLE';
```

### Step 2: Define Mappings
```sql
INSERT INTO config.metadata_registry
SELECT 
  'cerner' AS source_system,
  'VITAL_SIGNS' AS source_table,
  'TEMP_VALUE' AS source_column,
  'raw' AS target_schema,
  'vitals' AS target_table,
  'temperature_celsius' AS target_column,
  'NUMERIC(5,2)' AS data_type,
  'CASE WHEN TEMP_UNIT = ''F'' THEN (source_value - 32) * 5/9 ELSE source_value END' AS transformation_rule,
  true AS is_active;
```

### Step 3: Validation
```sql
-- Test transformation logic
SELECT 
  source_column,
  target_column,
  transformation_rule,
  -- Simulate transformation
  regexp_replace(transformation_rule, 'source_value', '''98.6''') AS test_expression
FROM config.metadata_registry
WHERE source_table = 'VITAL_SIGNS';
```

### Step 4: Deploy
```bash
# Trigger ingestion pipeline
python ingestion_orchestrator.py --source=cerner --table=VITAL_SIGNS --validate
python ingestion_orchestrator.py --source=cerner --table=VITAL_SIGNS --execute
```

## Change Management
```sql
-- Deactivate deprecated column
UPDATE config.metadata_registry
SET is_active = false
WHERE source_system = 'epic' AND source_column = 'OLD_FIELD';

-- Add new derived column
INSERT INTO config.metadata_registry VALUES
  ('epic', 'LAB_RESULTS', NULL, 'raw', 'labs', 'is_critical', 'BOOLEAN',
   'result_value > critical_high OR result_value < critical_low', true);
```

## Audit Trail
```sql
CREATE TABLE config.metadata_registry_audit (
  change_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  changed_by VARCHAR(100),
  change_type VARCHAR(20), -- INSERT, UPDATE, DELETE
  registry_record JSONB
);

-- Trigger on metadata changes
CREATE TRIGGER audit_metadata_changes
  AFTER INSERT OR UPDATE OR DELETE ON config.metadata_registry
  FOR EACH ROW EXECUTE FUNCTION log_metadata_change();
```

## Performance Optimization
- **Batch processing**: Group columns by transformation complexity
- **Parallel execution**: Partition large tables by source_system
- **Incremental loads**: Add `last_modified` tracking to metadata
- **Caching**: Materialize frequently-used transformations