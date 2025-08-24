# Basic Event Persistence

## Requirement
Create the events table and confirm we can append simple events to it and read those events back using Parrot integration.

## Design

### Database Schema
```sql
CREATE TABLE events (
  sequence_number BIGSERIAL PRIMARY KEY,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_type      TEXT        NOT NULL,
  payload         JSONB       NOT NULL,
  metadata        JSONB       NOT NULL DEFAULT '{}'
);
```

### Types
```gleam
pub type Event {
  Event(
    sequence_number: Int,
    occurred_at: String,
    event_type: String,
    payload: json.Json,
    metadata: json.Json
  )
}

pub type SimpleTestEvent {
  TestEvent(message: String)
}
```

### Core Functions
```gleam
pub fn append_event(db: Connection, event_type: String, payload: json.Json, metadata: json.Json) -> Result(Nil, AppendError)

pub fn read_all_events(db: Connection) -> Result(List(Event), ReadError)
```

### Database Connection
```gleam
pub fn connect() -> Result(Connection, ConnectionError)
```

## Task Breakdown

| Status | Task |
|--------|------|
| [x] | Create docker-compose.yml for PostgreSQL database |
| [x] | Set up Cigogne migration for events table |
| [x] | Create basic Event type to match table structure |
| [x] | Create SimpleTestEvent type for testing |
| [x] | Implement database connection function |
| [x] | Implement append_event function with Parrot |
| [x] | Implement read_all_events function with Parrot |
| [x] | Update tests to work with gleam types |
