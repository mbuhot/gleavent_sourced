# EventFilter to JSON Conversion for Fact Tagging

## Overview

This document explains how to convert Gleam `EventFilter` structures to the JSON format expected by the `ReadEventsWithFactTags` SQL query. This conversion is essential for the fact-event-isolation system.

## JSON Format Structure

The SQL query expects an array of filter objects, each containing:

```json
{
  "fact_id": "unique_fact_identifier",
  "event_type": "EventTypeName", 
  "filter": "$ ? ($.field == $param_name)",
  "params": {"param_name": "actual_value"}
}
```

## EventFilter Internal Structure

The Gleam `EventFilter` type contains:

```gleam
pub type EventFilter {
  EventFilter(filters: List(FilterCondition))
}

// Internal FilterCondition structure:
FilterCondition(
  event_type: String,
  filter_expr: String,     // JSONPath expression
  params: Dict(String, json.Json),
)
```

## Conversion Examples

### Simple Ticket ID Filter

**Gleam EventFilter:**
```gleam
event_filter.new()
|> event_filter.for_type("TicketOpened", [
  event_filter.attr_string("ticket_id", "T-100")
])
```

**JSON Output:**
```json
{
  "fact_id": "12345",
  "event_type": "TicketOpened",
  "filter": "$ ? ($.ticket_id == $ticket_id_param_0)",
  "params": {"ticket_id_param_0": "T-100"}
}
```

### Multiple Event Types for One Fact

**Gleam EventFilter:**
```gleam
event_filter.new()
|> event_filter.for_type("TicketOpened", [
  event_filter.attr_string("ticket_id", "T-100")
])
|> event_filter.for_type("TicketClosed", [
  event_filter.attr_string("ticket_id", "T-100") 
])
```

**JSON Output (multiple objects):**
```json
[
  {
    "fact_id": "12345",
    "event_type": "TicketOpened", 
    "filter": "$ ? ($.ticket_id == $ticket_id_param_0)",
    "params": {"ticket_id_param_0": "T-100"}
  },
  {
    "fact_id": "12345",
    "event_type": "TicketClosed",
    "filter": "$ ? ($.ticket_id == $ticket_id_param_0)", 
    "params": {"ticket_id_param_0": "T-100"}
  }
]
```

### Complex Filter with Multiple Attributes

**Gleam EventFilter:**
```gleam
event_filter.new()
|> event_filter.for_type("TicketOpened", [
  event_filter.attr_string("ticket_id", "T-100"),
  event_filter.attr_string("priority", "high")
])
```

**JSON Output:**
```json
{
  "fact_id": "12345",
  "event_type": "TicketOpened",
  "filter": "$ ? ($.ticket_id == $ticket_id_param_0 && $.priority == $priority_param_1)",
  "params": {
    "ticket_id_param_0": "T-100",
    "priority_param_1": "high"
  }
}
```

## Implementation Function Signature

```gleam
pub fn event_filter_to_json_with_id(
  fact_id: String,
  filter: event_filter.EventFilter
) -> List(json.Json) {
  // Convert EventFilter.filters to list of JSON objects
  // Each FilterCondition becomes one JSON object with fact_id
  todo "implement conversion"
}
```

## Key Implementation Notes

1. **Fact ID Inclusion**: Every JSON object must include the `fact_id` field
2. **Multiple Objects**: One EventFilter can produce multiple JSON objects (one per event type)
3. **Parameter Naming**: Maintain existing parameter naming conventions from EventFilter
4. **JSONPath Expressions**: Preserve existing JSONPath syntax from `filter_expr` field
5. **Parameter Values**: Convert from `Dict(String, json.Json)` to JSON object

## Usage in Facts System

```gleam
// In build_context function:
let filter_json = facts
  |> list.flat_map(fn(fact) {
    event_filter_to_json_with_id(fact.id, fact.event_filter)
  })
  |> json.array(fn(x) { x })

// Pass to SQL query:
let tagged_events = sql.read_events_with_fact_tags(db, filter_json)
```

## Compatibility Notes

- Must maintain compatibility with existing `ReadEventsWithFilter` JSON format
- Parameter naming and JSONPath syntax should match existing patterns
- The `fact_id` field is the only addition to the existing JSON structure