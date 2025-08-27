# Fact Event Isolation Problem

## Requirement

Eliminate the brittle duplication between `event_filter` (SQL-level filtering) and `apply_events` (application-level filtering) in facts. Currently, when facts are composed, all facts receive all events that match the combined filter, forcing each fact to manually re-filter events in `apply_events` to check if they actually match that specific fact's criteria.

## Current Architecture Problem

When multiple facts are composed:

```gleam
// Fact A wants: TicketOpened events for ticket "ABC-001"
event_filter: for_type_with_id("TicketOpened", "ABC-001")

// Fact B wants: TicketOpened events for ticket "XYZ-999"
event_filter: for_type_with_id("TicketOpened", "XYZ-999")
```

The combined filter loads ALL TicketOpened events for both tickets, then:
- Fact A's `apply_events` receives events for BOTH tickets but must manually filter for "ABC-001"
- Fact B's `apply_events` receives events for BOTH tickets but must manually filter for "XYZ-999"

This creates **brittle duplication** - the filtering logic exists in both the SQL filter AND the application logic.

## Multi-Ticket Use Cases That Motivate This Design

### Use Case 1: Ticket Relationship Commands
```gleam
// Command: "Mark ticket A as duplicate of ticket B"
pub type MarkDuplicateCommand {
  MarkDuplicateCommand(duplicate_ticket_id: String, original_ticket_id: String)
}

// Handler needs facts from BOTH tickets:
// - original_ticket must exist and be open
// - duplicate_ticket must exist and not already be marked duplicate
let facts = [
  ticket_facts.exists(command.original_ticket_id, update_original_context),
  ticket_facts.is_closed(command.original_ticket_id, update_original_context),
  ticket_facts.exists(command.duplicate_ticket_id, update_duplicate_context),
  ticket_facts.duplicate_status(command.duplicate_ticket_id, update_duplicate_context),
]
```

### Use Case 2: Cross-Ticket Validation
```gleam
// Command: "Close parent ticket" 
// Business rule: Can't close parent if child tickets are still open
pub type CloseParentTicketCommand {
  CloseParentTicketCommand(parent_id: String, child_ids: List(String))
}

// Handler needs facts from parent AND all children:
let parent_facts = [
  ticket_facts.exists(command.parent_id, update_parent_context),
  ticket_facts.is_closed(command.parent_id, update_parent_context),
]

let child_facts = list.flat_map(command.child_ids, fn(child_id) {
  [
    ticket_facts.exists(child_id, update_child_context),
    ticket_facts.is_closed(child_id, update_child_context),
  ]
})

let all_facts = list.append(parent_facts, child_facts)
```

### Use Case 3: Batch Operations
```gleam
// Command: "Bulk assign multiple tickets to user"
pub type BulkAssignCommand {
  BulkAssignCommand(ticket_ids: List(String), assignee: String)
}

// Handler needs facts from ALL tickets to validate they can be assigned:
let all_facts = list.flat_map(command.ticket_ids, fn(ticket_id) {
  [
    ticket_facts.exists(ticket_id, update_ticket_context),
    ticket_facts.is_closed(ticket_id, update_ticket_context), 
    ticket_facts.current_assignee(ticket_id, update_ticket_context),
  ]
})
```

**Why SQL Tagging Is Essential:**
- Without tagging: Each fact manually filters through events from ALL tickets
- With tagging: Each fact gets only events for the specific ticket(s) it cares about
- Consistency: Single query ensures all cross-ticket validations see same snapshot
- Performance: One query instead of N queries for N tickets

## Design Options

### Option 1: SQL-Level Event Tagging (Detailed Exploration)
Tag events during the SQL query to indicate which fact's filter they matched, ensuring consistent snapshot while providing isolated events per fact.

**Core Concept:**
Generate a single SQL query that:
1. Loads all events matching the combined filter (consistent snapshot)
2. Tags each event with which specific fact filters it matches
3. Allows application code to route events to correct facts without re-filtering

**Detailed Implementation:**

```gleam
pub type TaggedEvent {
  TaggedEvent(
    event: TicketEvent,
    matching_facts: List(String)  // IDs of facts this event matches
  )
}

// Updated Fact type with auto-generated unique ID
pub type Fact(event, context) {
  Fact(
    id: String,                                       // Auto-generated unique ID
    event_filter: event_filter.EventFilter,
    apply_events: fn(context, List(event)) -> context,
  )
}
```

**SQL Implementation Using Existing Query Structure:**
We can extend the existing `ReadEventsWithFilter` query to include fact IDs and return a `matching_facts` array:

**Input JSON Structure:**
```json
[
  {
    "fact_id": "exists_fact_ABC-001",
    "event_type": "TicketOpened",
    "filter": "$ ? ($.ticket_id == $ticket_id)",
    "params": {"ticket_id": "ABC-001"}
  },
  {
    "fact_id": "closed_fact_ABC-001",
    "event_type": "TicketClosed",
    "filter": "$ ? ($.ticket_id == $ticket_id)",
    "params": {"ticket_id": "ABC-001"}
  },
  {
    "fact_id": "exists_fact_XYZ-999",
    "event_type": "TicketOpened",
    "filter": "$ ? ($.ticket_id == $ticket_id)",
    "params": {"ticket_id": "XYZ-999"}
  }
]
```

**New SQL Query (`ReadEventsWithFactTags`):**
```sql
WITH filter_conditions AS (
  SELECT
    filter_config ->> 'fact_id' as fact_id,
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
),
events_with_tags AS (
  SELECT
    e.*,
    ARRAY(
      SELECT fc.fact_id
      FROM filter_conditions fc
      WHERE fc.event_type = e.event_type
        AND jsonb_path_exists(e.payload, fc.jsonpath_expr::jsonpath, fc.jsonpath_params)
    ) as matching_facts
  FROM matching_events e
)
SELECT *, matching_facts FROM events_with_tags ORDER BY sequence_number ASC;
```

**Application-Level Processing:**
```gleam
// Facts already have auto-generated unique IDs from erlang.unique_integer
let filter_json = facts
  |> list.map(fn(fact) {
    // Convert fact.event_filter to JSON format with fact_id
    event_filter_to_json_with_id(fact.id, fact.event_filter)
  })
  |> json.array(identity)

// Load tagged events with single query
let tagged_events = sql.read_events_with_fact_tags(db, filter_json)

// Route events to facts based on matching_facts array
let events_by_fact = tagged_events
  |> list.fold(dict.new(), fn(acc, tagged_event) {
    tagged_event.matching_facts
    |> list.fold(acc, fn(dict, fact_id) {
      dict.upsert(dict, fact_id, fn(existing) {
        [tagged_event.event, ..option.unwrap(existing, [])]
      })
    })
  })

// Each fact processes only its matching events
facts
|> list.fold(context, fn(ctx, fact) {
  let fact_events = dict.get(events_by_fact, fact.id)
    |> option.unwrap([])
    |> list.reverse()  // Restore chronological order
  fact.apply_events(ctx, fact_events)
})
```

**Concrete Example:**
Given facts:
- Fact A: `for_type_with_id("TicketOpened", "T-100")`
- Fact B: `for_type_with_id("TicketClosed", "T-100")`
- Fact C: `for_type_with_id("TicketOpened", "T-200")`

Events in database:
1. `TicketOpened("T-100", ...)` → matches Fact A only
2. `TicketClosed("T-100", ...)` → matches Fact B only
3. `TicketOpened("T-200", ...)` → matches Fact C only
4. `TicketAssigned("T-100", ...)` → matches no facts (filtered out)

Result: Each fact's `apply_events` receives exactly the events it should process.

**Pros:**
- **Consistent snapshot** - Single query ensures all facts see same point-in-time data
- **Perfect isolation** - Each fact gets only its matching events
- **Eliminates duplication** - No manual filtering needed in apply_events
- **Efficient** - One database round trip

**Cons:**
- **Complex SQL generation** - Need to analyze filters and generate CASE statements
- **Database-specific** - Relies on JSON operators (PostgreSQL `->>`), may not be portable
- **Query complexity** - Large number of facts creates unwieldy SQL
- **Filter analysis required** - Need to parse/understand filter structure to generate CASE clauses

**Implementation Challenges:**
1. **EventFilter to JSON Conversion:** Need function to convert `EventFilter` struct to JSON format with fact_id
2. **Consistent Query Interface:** Must maintain compatibility with existing `ReadEventsWithFilter` patterns
3. **Fact ID Generation:** Need strategy for generating unique fact IDs (simple indexing should work)
4. **Event Routing:** Application logic to group tagged events by fact IDs

**Key Advantages:**
- Leverages existing query infrastructure and JSON filter format
- Facts get auto-generated unique IDs using `erlang.unique_integer/0`
- No wrapper types needed - ID is part of core Fact type
- Minimal new SQL complexity

## Implementation Approach

We'll use the **SQL-Level Event Tagging** approach as it provides the best balance of consistency and performance.

## Task Breakdown

- [ ] Update `Fact` type in `facts.gleam` to include auto-generated `id` field using `erlang.unique_integer/0`
- [ ] Add a new_fact constructor function in facts.gleam to create a fact with auto-generated ID
- [ ] Create `event_filter_to_json_with_id` function to convert EventFilter + fact_id to JSON format
- [ ] Update `build_context` to use new `ReadEventsWithFactTags` query with fact ID tagging
- [ ] Add tests to verify fact isolation works correctly
- [ ] Add integration tests to ensure handler behavior unchanged

## Success Criteria

- Each fact's `apply_events` function receives only events that match its filter
- No manual event filtering needed in `apply_events` functions
- All existing tests continue to pass
- Command handlers work unchanged from external perspective

## Current System Context

### Key Files and Locations
- **Generic facts system**: `src/gleavent_sourced/facts.gleam` - contains core `Fact(event, context)` type and utilities
- **Ticket-specific facts**: `src/gleavent_sourced/customer_support/ticket_facts.gleam` - domain facts like `exists()`, `is_closed()`, etc.
- **SQL queries**: `src/gleavent_sourced/sql/events.sql` - already has `ReadEventsWithFilter`, new `ReadEventsWithFactTags` added
- **Command handlers**: `src/gleavent_sourced/customer_support/{assign,close}_ticket_handler.gleam` - use facts via `ticket_commands.make_handler()`
- **Integration point**: `src/gleavent_sourced/customer_support/ticket_commands.gleam` - `make_handler()` calls `facts.event_filter()` and `facts.build_context()`

### Current Fact Architecture
```gleam
// Current Fact type (in facts.gleam)
pub type Fact(event, context) {
  Fact(
    event_filter: event_filter.EventFilter,
    apply_events: fn(context, List(event)) -> context,
  )
}

// Current ticket facts use fold_into helper for conciseness
pub fn exists(ticket_id: String, update_context: fn(context, Bool) -> context) -> facts.Fact(TicketEvent, context) {
  facts.Fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    apply_events: fold_into(update_context, False, fn(acc, event) { /* ... */ })
  )
}
```

### Testing Context
- **All tests passing**: 11/11 unit tests, 7/7 integration tests in `test/gleavent_sourced/command_handler_test.gleam`
- **Handler compatibility**: `open_ticket_handler` unchanged, `assign_ticket_handler` and `close_ticket_handler` converted to facts
- **Integration approach**: Focus on keeping existing `ticket_command_router` interface unchanged

### Implementation Notes
- **Erlang unique_integer**: Use `int.to_string(erlang.unique_integer([]))` for fact IDs
- **JSON conversion**: Need to convert `EventFilter` to JSON format that matches existing `ReadEventsWithFilter` structure
- **Event routing**: Application-level grouping by `matching_facts` array from SQL results
- **Helper functions**: Leverage existing `fold_into()` and `for_type_with_id()` patterns

### Architecture Constraints
- **Command-specific handlers**: Handlers are created per command instance (not singleton)
- **Fact isolation**: Each fact should only process events that match its filter
- **Static event filters**: CommandHandler uses static EventFilter (not function)
- **Generic reusability**: Core fact system must work for other domains beyond tickets
