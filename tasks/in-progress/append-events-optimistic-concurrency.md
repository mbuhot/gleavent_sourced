# Append Events with Optimistic Concurrency Control

## Requirement
Update `append_events` to accept an `EventFilter` parameter and last seen sequence number to implement optimistic concurrency control, preventing conflicting concurrent modifications by checking if any new events matching the filter have been logged since the command handler last read the event stream.

## Design

### Types
```gleam
// New result type for append operations
pub type AppendResult {
  AppendSuccess
  AppendConflict(
    conflict_count: Int, 
    latest_sequence: Int
  )
}

// Updated function signature 
pub fn append_events(
  db: pog.Connection,
  events: List(event_type),
  event_converter: fn(event_type) -> #(String, json.Json),
  metadata: String,
  conflict_filter: EventFilter,
  last_seen_sequence: Int,
) -> Result(AppendResult, pog.QueryError)
```

### SQL Design
- Single CTE-based prepared statement combining conflict detection and batch insert
- Three CTEs: filter_conditions, conflict_check, batch_insert 
- Return status, conflict info, and inserted sequence numbers in one query
- Use conditional insert based on conflict_count = 0

### High-Level Flow
1. Convert EventFilter to JSON for SQL parameter
2. Convert all events to JSON array for batch processing
3. Execute single CTE query with conflict detection + batch insert
4. Parse results into AppendResult variants
5. Return success or conflict with details

## Task Breakdown

- [x] Add `AppendResult` type to `event_log.gleam`
- [x] Update SQL module with CTE-based batch insert with conflict checking
- [x] Add SQL function `batch_insert_events_with_conflict_check` with decoder
- [x] Update `append_events` function signature to accept filter and last_seen_sequence
- [x] Implement conflict detection logic in `append_events`
- [x] Add helper function to convert events list to JSON array format
- [x] Update all existing `append_events` call sites to provide empty filter + sequence 0
- [x] Write test for successful batch insert (no conflicts)
- [x] Write test for conflict detection (events added since last read)
- [x] Write test for mixed scenario (demonstrates all-or-nothing batch behavior)
- [x] Write test for empty events list with conflict filter
- [x] Update existing tests to handle new function signature