# Task: Optimize EventFilter System to Use PostgreSQL Indexed JSONB Operators

## Overview
Refactor the Gleam EventFilter module and corresponding SQL queries to use PostgreSQL's indexed JSONB operators (`@>`, `?`, `?|`, `?&`) instead of `jsonb_path_exists()` for dramatically improved performance.

## Current System Problems
- Uses `jsonb_path_exists()` which requires sequential table scans
- No index utilization for filtering operations
- Poor performance on large datasets

## Target System Benefits
- Uses GIN indexed operators for O(log n) performance
- All filter operations will utilize PostgreSQL indexes
- Maintains same API for calling code - **NO BREAKING CHANGES**

## Required Changes

### 1. Update Gleam EventFilter Module

**File to modify:** The EventFilter module provided

**Key Changes:**

#### A. Modify JSON Output Format
Change from JSONPath format:
```json
{
  "fact_id": "tag",
  "event_type": "EventType",
  "filter": "$ ? ($.field == $param)",
  "params": {"param": "value"}
}
```

To indexed operator format:
```json
{
  "fact_id": "tag",
  "event_type": "EventType",
  "operator": "containment|key_exists|comparison|null_check",
  "filter": {...} // format varies by operator
}
```

#### B. AttributeFilter to Operator Mapping
Map each `AttributeFilter` type to the appropriate indexed operator:

| AttributeFilter | PostgreSQL Operator | New Format |
|-----------------|-------------------|------------|
| `StringEquals(field, value)` | `@>` | `{"operator": "containment", "filter": {"field": "value"}}` |
| `IntEquals(field, value)` | `@>` | `{"operator": "containment", "filter": {"field": value}}` |
| `BoolEquals(field, value)` | `@>` | `{"operator": "containment", "filter": {"field": value}}` |
| `FieldIsNull(field)` | `@>` | `{"operator": "containment", "filter": {"field": null}}` |
| `IntGreaterThan(field, value)` | Custom | `{"operator": "comparison", "filter": {"field": "field", "op": ">", "value": value}}` |
| `IntLessThan(field, value)` | Custom | `{"operator": "comparison", "filter": {"field": "field", "op": "<", "value": value}}` |

#### C. Update Core Functions
- **`combine_attribute_filters_to_condition()`**: Generate operator-based conditions instead of JSONPath
- **`attribute_filter_to_condition_part()`**: Convert each filter type to appropriate operator format
- **`to_string()`**: Output new JSON structure

#### D. Handle Multiple Filters
For multiple `AttributeFilter`s on same event type (AND logic):
- Equality filters: Merge into single containment object: `{"field1": "val1", "field2": "val2"}`
- Mixed filters: Create array of filter objects with explicit AND logic

### 2. Update SQL Queries

**File to modify:** The SQL file with `ReadEventsWithFactTags` and `BatchInsertEventsWithConflictCheck`

**Key Changes:**

#### A. Update filter_conditions CTE
Change from:
```sql
SELECT
  filter_config ->> 'fact_id' as fact_id,
  filter_config ->> 'event_type' as event_type,
  filter_config ->> 'filter' as jsonpath_expr,
  filter_config -> 'params' as jsonpath_params
```

To:
```sql
SELECT
  filter_config ->> 'fact_id' as fact_id,
  filter_config ->> 'event_type' as event_type,
  filter_config ->> 'operator' as operator_type,
  filter_config -> 'filter' as filter_value
```

#### B. Replace WHERE Conditions
Change from:
```sql
WHERE jsonb_path_exists(e.payload, fc.jsonpath_expr::jsonpath, fc.jsonpath_params)
```

To:
```sql
WHERE
  (fc.operator_type = 'containment' AND e.payload @> fc.filter_value)
  OR
  (fc.operator_type = 'key_exists' AND e.payload ? (fc.filter_value ->> 'key'))
  OR
  (fc.operator_type = 'comparison' AND
    CASE fc.filter_value ->> 'op'
      WHEN '>' THEN (e.payload -> (fc.filter_value ->> 'field'))::int > (fc.filter_value ->> 'value')::int
      WHEN '<' THEN (e.payload -> (fc.filter_value ->> 'field'))::int < (fc.filter_value ->> 'value')::int
      ELSE false
    END
  )
```

#### C. Update Both Queries
Apply these changes to:
1. **`ReadEventsWithFactTags`**: Both the `matching_events` CTE and the `events_with_tags` subquery
2. **`BatchInsertEventsWithConflictCheck`**: The `conflict_check` CTE

### 3. Required Database Indexes

Ensure these indexes exist for optimal performance:
```sql
-- Primary index for JSONB containment operations
CREATE INDEX IF NOT EXISTS idx_events_payload_gin ON events USING gin(payload);

-- Supporting indexes
CREATE INDEX IF NOT EXISTS idx_events_event_type ON events (event_type);
CREATE INDEX IF NOT EXISTS idx_events_sequence_number ON events (sequence_number);
```

## Implementation Strategy

### Phase 1: Update Gleam Module
1. Modify the `AttributeFilter` to operator conversion logic
2. Update JSON serialization to new format
3. Test with simple equality filters first

### Phase 2: Update SQL Queries
1. Modify the `filter_conditions` CTE structure
2. Replace `jsonb_path_exists()` with indexed operators
3. Ensure both read and insert queries use same logic

### Phase 3: Testing
1. Verify existing tests pass without modification
2. Confirm performance improvements with `EXPLAIN ANALYZE`
3. Test edge cases (null values, missing fields, etc.)

## Expected Performance Improvement

| Operation | Before (JSONPath) | After (Indexed) | Improvement |
|-----------|------------------|-----------------|-------------|
| Simple equality | Sequential scan | Index scan | 10-100x faster |
| Multiple filters | Multiple seq scans | Multiple index scans | 20-200x faster |
| Large tables (1M+ rows) | 2-10 seconds | 10-50ms | 100-1000x faster |

## Success Criteria
- [ ] All existing tests pass without modification
- [ ] Query execution plans show index usage instead of sequential scans
- [ ] Performance benchmarks show significant improvement
- [ ] Both read and insert queries work correctly
- [ ] Backward compatibility maintained for calling code

## Key Files to Modify
1. **EventFilter Gleam module**: Change filter generation logic
2. **SQL queries file**: Replace JSONPath with indexed operators
3. **No changes needed**: Tests, calling code, or external APIs

## Notes
- Prioritize `StringEquals`, `IntEquals`, `BoolEquals` as they map cleanly to containment
- Handle `IntGreaterThan`/`IntLessThan` as comparison operators (may not use indexes)
- Consider `FieldIsNull` as containment with `null` value
- Maintain exact same external API and behavior
- Focus on performance while preserving functionality
