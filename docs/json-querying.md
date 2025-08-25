# JSON Querying Patterns in Event Sourced Systems

This document covers techniques for querying JSON event payloads in PostgreSQL-backed event sourced applications.

## Overview

Event sourcing systems store event payloads as JSON, enabling flexible schema evolution. PostgreSQL provides powerful JSON querying capabilities that allow efficient filtering and extraction of event data.

## JSON Field Extraction with `->`

### Simple Field Access

Use `payload->>'field_name'` to extract JSON fields as text:

```sql
-- Find all ticket events for a specific ticket
SELECT * FROM events 
WHERE event_type = 'TicketOpened' 
  AND payload->>'ticket_id' = 'T-001';
```

### Nested Field Access

Access nested fields using JSON path syntax:

```sql
-- Access nested customer information
SELECT * FROM events 
WHERE payload->>'customer'->>'id' = 'CUST-123';
```

### Multiple Event Types with Same Field

Combine different event types that share common fields:

```sql
-- All ticket-related events for a specific ticket
SELECT sequence_number, occurred_at, event_type, payload, metadata
FROM events
WHERE (event_type = 'TicketOpened' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketAssigned' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketClosed' AND payload->>'ticket_id' = @ticket_id)
ORDER BY sequence_number;
```

## Advanced JSONPath Filtering

### JSONPath with Parameter Substitution

Use `jsonb_path_exists()` for complex filtering with parameters:

```sql
-- Generic filtering system
WITH filter_conditions AS (
  SELECT
    filter_config ->> 'event_type' as event_type,
    filter_config ->> 'filter' as jsonpath_expr,
    filter_config -> 'params' as jsonpath_params
  FROM jsonb_array_elements(@filters) AS filter_config
),
matching_events AS (
  SELECT DISTINCT e.*
  FROM events e
  JOIN filter_conditions fc ON e.event_type = fc.event_type
  WHERE jsonb_path_exists(e.payload, fc.jsonpath_expr::jsonpath, fc.jsonpath_params)
)
SELECT *, (SELECT MAX(sequence_number) FROM matching_events) as current_max_sequence
FROM matching_events
ORDER BY sequence_number ASC;
```

### JSONPath Syntax Examples

| Pattern | JSONPath Expression | Description |
|---------|---------------------|-------------|
| Field equals value | `$.priority ? (@ == $priority)` | Check if field matches parameter |
| Field exists | `$.assignee ? (@.type() != "null")` | Check if field is not null |
| Numeric comparison | `$.amount ? (@ > $min_amount)` | Numeric greater than |
| Array contains | `$.tags ? (@ == $tag)` | Array contains specific value |
| Nested field | `$.customer.tier ? (@ == $tier)` | Access nested object field |

### Filter Configuration Example

```gleam
// Create JSONPath filter in Gleam
let filters_json = json.array(of: json.object, from: [
  [
    #("event_type", json.string("TicketOpened")),
    #("filter", json.string("$.priority ? (@ == $priority)")),
    #("params", json.object([
      #("priority", json.string("high"))
    ]))
  ]
]) |> json.to_string

// Execute filter
let #(sql, params, decoder) = sql.read_events_with_filter(filters: filters_json)
```

## Performance Optimization

### GIN Indexes

Create GIN indexes on JSON columns for efficient querying:

```sql
-- Index for general JSON operations
CREATE INDEX idx_events_payload_gin ON events USING gin (payload);

-- Index for specific JSON paths (PostgreSQL 14+)
CREATE INDEX idx_events_ticket_id ON events USING gin ((payload->'ticket_id'));
```

### Query Performance Tips

1. **Use GIN indexes** for JSON columns with frequent queries
2. **Filter by event_type first** to reduce the search space
3. **Use `->>`** for simple field extraction (faster than JSONPath)
4. **Use JSONPath** only when you need complex filtering logic
5. **Index commonly accessed fields** with expression indexes

## Common Patterns

### Business Context Queries

Query all events needed for a specific command handler:

```sql
-- name: ReadEventsForTicketCommandContext :many
SELECT sequence_number, occurred_at, event_type, payload, metadata
FROM events
WHERE (event_type = 'TicketOpened' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketAssigned' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketClosed' AND payload->>'ticket_id' = @ticket_id)
ORDER BY sequence_number;
```

### Priority-Based Filtering

Filter events by business priority or category:

```sql
-- High priority tickets only
SELECT * FROM events 
WHERE event_type = 'TicketOpened' 
  AND payload->>'priority' IN ('high', 'critical');
```

### Time-Range with JSON Filtering

Combine temporal and JSON filtering:

```sql
-- Recent high-priority tickets
SELECT * FROM events 
WHERE occurred_at > NOW() - INTERVAL '7 days'
  AND event_type = 'TicketOpened'
  AND payload->>'priority' = 'high';
```

### Customer Segmentation

Filter events by customer attributes:

```sql
-- Enterprise customer events
SELECT * FROM events
WHERE payload->>'customer_tier' = 'enterprise'
  AND occurred_at > @since_date;
```

## Integration with Gleam

### Type-Safe JSON Handling

Always convert JSON to proper types immediately after extraction:

```gleam
// In gleavent_sourced/events.gleam
pub fn decode_ticket_events(
  raw_events: List(sql.ReadEventsByTypes),
  payload_decoder: decode.Decoder(payload),
) -> Result(List(Event(payload)), json.DecodeError) {
  list.try_map(raw_events, fn(raw_event) {
    json.parse(raw_event.payload, payload_decoder)
    |> result.map(fn(decoded_payload) {
      Event(
        sequence_number: raw_event.sequence_number,
        occurred_at: raw_event.occurred_at,
        event_type: raw_event.event_type,
        payload: decoded_payload,
        metadata: raw_event.metadata,
      )
    })
  })
}
```

### Parameterized Queries

Use Parrot's parameter binding for safe JSON queries:

```gleam
// Generated by Parrot
pub fn read_events_for_ticket_command_context(ticket_id ticket_id: String) {
  let sql = "SELECT ... WHERE payload->>'ticket_id' = $1"
  #(sql, [dev.ParamString(ticket_id)], decoder())
}
```

## Error Handling

### JSON Parse Errors

Handle malformed JSON gracefully:

```gleam
case json.parse(raw_event.payload, ticket_decoder()) {
  Ok(event) -> event
  Error(_) -> {
    // Log error, use default, or skip event
    default_ticket_event()
  }
}
```

### Missing Fields

Use decoders with defaults for optional fields:

```gleam
pub fn ticket_decoder() -> decode.Decoder(TicketEvent) {
  use ticket_id <- decode.field("ticket_id", decode.string)
  use priority <- decode.optional_field("priority", decode.string)
  decode.success(TicketOpened(
    ticket_id: ticket_id,
    priority: option.unwrap(priority, "medium"),
    // ...
  ))
}
```

## Best Practices

### 1. Schema Evolution

Design JSON schemas that can evolve:

```gleam
// Good: Optional fields with defaults
TicketOpened(
  ticket_id: String,        // Required, never changes
  title: String,            // Required, never changes  
  priority: Option(String), // Optional, can be added later
  tags: List(String),       // Lists can start empty
)
```

### 2. Query Optimization

- Start with the most selective filters (usually `event_type`)
- Use simple field extraction (`->>`) when possible
- Reserve JSONPath for complex filtering logic
- Create indexes for frequently queried fields

### 3. Parameter Safety

Always use parameterized queries to prevent injection:

```sql
-- Safe: Using parameter
WHERE payload->>'user_id' = @user_id

-- Unsafe: String concatenation
WHERE payload->>'user_id' = '" <> user_id <> "'"
```

### 4. Testing JSON Queries

Test JSON queries with realistic data:

```gleam
pub fn test_high_priority_filter() {
  // Create events with various priorities
  let events = [
    create_ticket("high"), 
    create_ticket("medium"),
    create_ticket("low")
  ]
  
  // Test filter returns only high priority
  let high_priority = query_by_priority("high")
  assert list.length(high_priority) == 1
}
```

This approach to JSON querying provides both flexibility for complex business queries and performance through proper indexing and query optimization.