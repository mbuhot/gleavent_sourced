# Enhanced Event Querying with JsonPath

## Requirement
Add the ability to query events by their JSON payload attributes using PostgreSQL's JSON operators, allowing business context queries like "find all ticket events (TicketOpened, TicketAssigned, TicketClosed) for ticket T-001".

## Design

### Approach
- Use Parrot (sqlc for Gleam) to write business-purpose SQL queries directly
- Each query designed for specific command handler context needs
- Use PostgreSQL's `payload->>'field_name'` operator for JSON field extraction
- Combine multiple event types with OR logic in single query

### Example Implementation
```sql
-- name: ReadEventsForTicketCommandContext :many
SELECT sequence_number, occurred_at, event_type, payload, metadata
FROM events
WHERE (event_type = 'TicketOpened' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketAssigned' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketClosed' AND payload->>'ticket_id' = @ticket_id)
ORDER BY sequence_number;
```

### Generated Function
```gleam
pub fn read_events_for_ticket_command_context(ticket_id ticket_id: String)
pub fn decode_ticket_command_context_payloads(...)
```

### Database Schema Changes
- Add GIN index on payload column to support jsonpath operations: `CREATE INDEX CONCURRENTLY idx_events_payload_gin ON events USING gin (payload);`

## Task Breakdown

- [x] Create database migration to add GIN index on payload column
- [x] Create SQL query for ticket command context using PostgreSQL JSON operators
- [x] Regenerate sql.gleam using Parrot to get type-safe function
- [x] Create decode function for new query result type
- [x] Write test for querying all events for a specific ticket_id
- [x] Write test verifying query filters correctly (different tickets return different results)
- [x] Write test for non-existent ticket_id (returns empty results)

## Implementation Notes

- Used `payload->>'field_name'` instead of jsonpath `@?` for simplicity and sqlc compatibility
- Built specific query for ticket context rather than generic filtering system
- GIN index supports JSON operations and will improve performance on larger datasets
- Pattern established for adding more business-purpose queries as needed