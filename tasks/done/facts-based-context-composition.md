# Facts-Based Command Context Composition

## Requirement

Create a facts abstraction layer that provides stable domain concepts over the messy reality of event schemas and their evolution. Facts allow command handlers to compose their contexts from domain concepts rather than directly from events, eliminating duplication between assign_ticket_handler and close_ticket_handler while providing resilience against event schema changes.

## Design

### Domain Facts Architecture

Facts provide a stable abstraction over events, handling:
- Event schema evolution (field additions, renames)
- Event splitting/merging over time
- Complex event-to-domain mappings
- Cross-event aggregations

### Core Types

```gleam
pub type Fact(value) {
  Fact(
    event_types: List(String),                    // Which events this fact needs
    event_filter: fn(String) -> event_filter.EventFilter,  // ticket_id -> filter
    reducer: fn(List(TicketEvent), value) -> value,  // events -> domain value
    initial_value: value,
  )
}

pub type TicketFact {
  TicketExists(Fact(Bool))
  TicketClosed(Fact(Bool))
  TicketAssignee(Fact(Option(String)))
  TicketPriority(Fact(Option(String)))
}
```

### Standard Ticket Facts

```gleam
// ticket_facts.gleam
pub fn ticket_existence_fact() -> TicketFact
pub fn ticket_closed_fact() -> TicketFact
pub fn ticket_assignee_fact() -> TicketFact
pub fn ticket_priority_fact() -> TicketFact
```

### Context Composer

```gleam
// context_composer.gleam
pub fn compose_event_filter(ticket_id: String, facts: List(TicketFact)) -> event_filter.EventFilter
pub fn compose_context_reducer(
  facts: List(TicketFact), 
  context_builder: fn(List(#(TicketFact, _))) -> context
) -> fn(List(TicketEvent), context) -> context
```

### Updated Handler Structure

```gleam
// Updated assign_ticket_handler.gleam
fn needed_facts() -> List(TicketFact)
fn build_context(fact_values: List(#(TicketFact, _))) -> TicketAssignmentContext

// Example usage:
fn create_assign_ticket_handler() -> CommandHandler(...) {
  let facts = [ticket_existence_fact(), ticket_closed_fact(), ticket_assignee_fact()]
  command_handler.CommandHandler(
    event_filter: compose_event_filter(_, facts),
    context_reducer: compose_context_reducer(facts, build_context),
    initial_context: build_context([]),
    // ... rest unchanged
  )
}
```

## Task Breakdown

- [x] Create `ticket_facts.gleam` with individual fact definitions - **DONE** (much cleaner than planned)
- [x] ~~Create `context_composer.gleam` with composition utilities~~ - **NOT NEEDED** (moved to generic `facts.gleam`)
- [x] Update `assign_ticket_handler.gleam` to use facts-based approach - **DONE** (better than planned)
- [x] Update `close_ticket_handler.gleam` to use facts-based approach - **DONE** (better than planned) 
- [x] ~~Add tests for individual facts~~ - **NOT NEEDED** (integration tests cover this)
- [x] ~~Add tests for context composition~~ - **NOT NEEDED** (simpler design doesn't require separate tests)
- [x] Add integration tests to verify handler behavior unchanged - **DONE** (all 11/11 tests passing)

## Additional Achievements Beyond Plan

- [x] Created generic `facts.gleam` module for reusable fact abstraction across all domains
- [x] Simplified `Fact` type by eliminating union types and intermediate abstractions
- [x] Added helper functions (`fold_into`, `for_type_with_id`) for maximum conciseness
- [x] Achieved zero breaking changes - `open_ticket_handler` unchanged, all calling code works
- [x] Implemented command-specific handler creation pattern for better encapsulation