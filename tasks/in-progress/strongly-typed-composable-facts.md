# Strongly-Typed Composable Facts with Direct SQL

## 🎯 Executive Summary

**STATUS: CORE SYSTEM COMPLETE ✅**

The strongly-typed composable facts system has been successfully implemented with comprehensive testing including end-to-end database integration. All tests are passing.

### ✅ What's Working
- **SQL Composition**: Multi-fact CTE generation with parameter offsetting
- **Database Integration**: Real PostgreSQL operations with event decoding
- **Complex SQL Support**: Subqueries, window functions, parameter type casting
- **Performance**: Single query eliminates N+1 problems
- **Type Safety**: Facts compose regardless of internal value types

### 🔄 What's Remaining
- Migrate existing command handlers (`assign_ticket_handler`, `close_ticket_handler`)
- Create convenience functions in `ticket_facts.gleam`
- Remove deprecated modules (`event_filter.gleam`, `facts.gleam`)

### 🏗️ Architecture Achieved
```gleam
// Define facts with embedded SQL
let facts = [
  facts_v2.new_fact(sql: "SELECT * FROM events WHERE ...", params: [...], apply_events: ...),
  facts_v2.new_fact(sql: "SELECT * FROM events WHERE ...", params: [...], apply_events: ...),
]

// Single database query with automatic CTE composition
facts_v2.query_event_log(db, facts, initial_context, event_decoder)
// Returns: Updated context from all facts
```

The core challenge of **composable SQL generation** has been solved.

## Requirement

Replace the current facts system with a strongly-typed approach where application developers define domain facts as parameterized types with embedded SQL queries and reducer functions. The framework composes these into a single optimized CTE query, eliminating the need for the fluent EventFilter API and providing direct SQL composability for complex domain queries.

## Design

### Core Types

```gleam
// Core fact type with embedded SQL and reducer
pub type Fact(context, value) {
  Fact(
    id: String,                              // Unique identifier for CTE naming
    sql: String,                             // Raw SQL query with $1, $2, etc. placeholders
    params: List(pog.Value),                 // Parameters for the SQL query
    reducer: fn(List(event), value) -> value, // Function to process matched events
    initial_value: value,                    // Starting value for the reducer
    update_context: fn(context, value) -> context, // How to merge result into context
  )
}

// Domain-specific fact types for tickets
pub type TicketFact(context) {
  TicketExists(id: String, update_context: fn(context, Bool) -> context)
  TicketClosed(id: String, update_context: fn(context, Bool) -> context)
  TicketStatus(id: String, update_context: fn(context, Status) -> context)
  CurrentAssignee(id: String, update_context: fn(context, Option(String)) -> context)
  AllChildTicketsClosed(id: String, update_context: fn(context, Bool) -> context)
  ChildTicketCount(parent_id: String, update_context: fn(context, Int) -> context)
}
```

### Fact Implementation Pattern

```gleam
// ticket_facts.gleam
pub fn exists(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> Fact(context, Bool) {
  Fact(
    id: generate_unique_id(),
    sql: "SELECT * FROM events e WHERE e.event_type = 'TicketOpened' AND e.payload @> jsonb_build_object('ticket_id', $1)",
    params: [pog.text(ticket_id)],
    reducer: fn(events, _acc) {
      case events {
        [] -> False
        _ -> True
      }
    },
    initial_value: False,
    update_context: update_context,
  )
}

pub fn all_child_tickets_closed(
  parent_ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> Fact(context, Bool) {
  Fact(
    id: generate_unique_id(),
    sql: "
      SELECT e.* FROM events e
      WHERE e.event_type IN ('TicketParentLinked', 'TicketClosed')
      AND (
        e.payload @> jsonb_build_object('parent_ticket_id', $1) OR
        e.payload @> jsonb_build_object('ticket_id',
          (SELECT child_events.payload->>'child_ticket_id'
           FROM events child_events
           WHERE child_events.event_type = 'TicketParentLinked'
           AND child_events.payload @> jsonb_build_object('parent_ticket_id', $1)))
      )
    ",
    params: [pog.text(parent_ticket_id)],
    reducer: fn(events, _acc) {
      // Complex logic to determine if all children are closed
      let child_tickets = extract_child_ticket_ids(events)
      let closed_tickets = extract_closed_ticket_ids(events)
      list.all(child_tickets, fn(child_id) {
        list.contains(closed_tickets, child_id)
      })
    },
    initial_value: True, // Default to true (no children = all closed)
    update_context: update_context,
  )
}

// Helper function that maps TicketFact variants to concrete Fact instances
pub fn to_fact(ticket_fact: TicketFact(context)) -> Fact(context, _) {
  case ticket_fact {
    TicketExists(id, update_context) -> exists(id, update_context)
    TicketClosed(id, update_context) -> is_closed(id, update_context)
    TicketStatus(id, update_context) -> status(id, update_context)
    CurrentAssignee(id, update_context) -> current_assignee(id, update_context)
    AllChildTicketsClosed(id, update_context) -> all_child_tickets_closed(id, update_context)
    ChildTicketCount(parent_id, update_context) -> child_ticket_count(parent_id, update_context)
  }
}
```

### SQL Composition Engine

```gleam
// facts_composer.gleam
pub type ComposedQuery {
  ComposedQuery(sql: String, params: List(pog.Value))
}

pub fn compose_facts(facts: List(Fact(context, _))) -> ComposedQuery {
  let ctes = list.index_map(facts, fn(fact, index) {
    let cte_name = "fact_" <> int.to_string(index)
    let #(adjusted_sql, param_offset) = adjust_parameter_indices(fact.sql, get_param_offset(facts, index))
    #(cte_name, adjusted_sql)
  })

  let all_params = list.flatten(list.map(facts, fn(fact) { fact.params }))

  let cte_clauses =
    list.map(ctes, fn(cte) {
      let #(name, sql) = cte
      name <> " AS (" <> sql <> ")"
    })
    |> string.join(", ")

  let union_clause =
    list.index_map(facts, fn(fact, index) {
      let cte_name = "fact_" <> int.to_string(index)
      "SELECT '" <> fact.id <> "' as fact_id, * FROM " <> cte_name
    })
    |> string.join(" UNION ALL ")

  let final_sql =
    "WITH " <> cte_clauses <>
    ", all_events AS (" <> union_clause <> ")" <>
    " SELECT fact_id, sequence_number, event_type, payload, metadata" <>
    " FROM all_events ORDER BY sequence_number"

  ComposedQuery(sql: final_sql, params: all_params)
}

// Context building from query results
pub fn build_context(
  facts: List(Fact(context, _)),
  events_by_fact: dict.Dict(String, List(event)),
  initial_context: context,
) -> context {
  list.fold(facts, initial_context, fn(context_acc, fact) {
    let fact_events = dict.get(events_by_fact, fact.id) |> result.unwrap([])
    let reduced_value = fact.reducer(fact_events, fact.initial_value)
    fact.update_context(context_acc, reduced_value)
  })
}
```

### Command Handler Integration

```gleam
// Updated command handler usage
pub fn assign_ticket_handler() -> CommandHandler(...) {
  fn(ticket_id: String) {
    let facts = [
      ticket_facts.to_fact(ticket_facts.TicketExists(ticket_id, set_ticket_exists)),
      ticket_facts.to_fact(ticket_facts.TicketClosed(ticket_id, set_ticket_closed)),
      ticket_facts.to_fact(ticket_facts.CurrentAssignee(ticket_id, set_current_assignee)),
    ]

    CommandHandler(
      facts: facts,
      handle: handle_assign_ticket,
      initial_context: AssignTicketContext(
        ticket_exists: False,
        ticket_closed: False,
        current_assignee: None,
      ),
    )
  }
}

// Context setter functions
fn set_ticket_exists(context: AssignTicketContext, exists: Bool) -> AssignTicketContext {
  AssignTicketContext(..context, ticket_exists: exists)
}

fn set_ticket_closed(context: AssignTicketContext, closed: Bool) -> AssignTicketContext {
  AssignTicketContext(..context, ticket_closed: closed)
}

fn set_current_assignee(context: AssignTicketContext, assignee: Option(String)) -> AssignTicketContext {
  AssignTicketContext(..context, current_assignee: assignee)
}
```

### Advanced SQL Composition Examples

```gleam
// Complex cross-aggregate fact
pub fn team_workload_balance(
  team_members: List(String),
  update_context: fn(context, WorkloadBalance) -> context,
) -> Fact(context, WorkloadBalance) {
  let member_params = list.map(team_members, pog.text)
  let member_placeholders =
    list.index_map(team_members, fn(_, i) { "$" <> int.to_string(i + 1) })
    |> string.join(", ")

  Fact(
    id: generate_unique_id(),
    sql: "
      SELECT * FROM events e
      WHERE (e.event_type = 'TicketAssigned' AND e.payload->>'assignee' = ANY(ARRAY[" <> member_placeholders <> "]))
      OR (e.event_type = 'TicketClosed' AND EXISTS (
        SELECT 1 FROM events assign_e
        WHERE assign_e.event_type = 'TicketAssigned'
        AND assign_e.payload->>'ticket_id' = e.payload->>'ticket_id'
        AND assign_e.payload->>'assignee' = ANY(ARRAY[" <> member_placeholders <> "])
      ))
    ",
    params: list.append(member_params, member_params), // Duplicated for both clauses
    reducer: fn(events, _acc) {
      // Process assignment and closure events to calculate current workload per member
      let assignments = extract_current_assignments(events)
      let assignment_counts = count_assignments_per_member(assignments, team_members)
      let max_assignments = list.fold(assignment_counts, 0, int.max)
      let min_assignments = list.fold(assignment_counts, max_assignments, int.min)
      WorkloadBalance(
        balanced: max_assignments - min_assignments <= 1,
        max_difference: max_assignments - min_assignments
      )
    },
    initial_value: WorkloadBalance(balanced: True, max_difference: 0),
    update_context: update_context,
  )
}
```

### Migration Strategy

1. **Phase 1**: Create new fact types alongside existing system
2. **Phase 2**: Migrate one command handler at a time to new system
3. **Phase 3**: Remove old `event_filter.gleam` and current `facts.gleam`
4. **Phase 4**: Update all calling code to use new fact types

### Benefits

- **Strongly Typed**: Facts are parameterized types that enforce correct usage
- **Direct SQL**: No abstraction layer - developers write exactly the SQL they need
- **Composable**: Multiple facts automatically composed into single optimized query
- **Flexible**: Can handle simple attribute lookups or complex cross-aggregate queries
- **Maintainable**: Each fact encapsulates its SQL, parameters, and reduction logic
- **Testable**: Individual facts can be tested in isolation

## Task Breakdown

### ✅ COMPLETED: Core System (Phase 1)
- [x] **Create `Fact` type and helper functions in new `facts_v2.gleam`**
  - ✅ `Fact(context, event_type)` type with embedded SQL and context update
  - ✅ `new_fact()` constructor with auto-generated sequential IDs
  - ✅ `compose_facts()` - robust SQL composition with CTE generation
  - ✅ `build_context()` - context building from query results
  - ✅ `query_event_log()` - full database query pipeline

- [x] **SQL Composition Engine** *(integrated into facts_v2.gleam)*
  - ✅ Multi-fact CTE composition with `UNION ALL`
  - ✅ Parameter offset adjustment for multiple facts
  - ✅ Subquery wrapping without modifying user SQL
  - ✅ Window functions for efficient max sequence calculation
  - ✅ Sequential fact ID generation (`fact_1`, `fact_2`, etc.)

- [x] **Database Query Execution** *(integrated into facts_v2.gleam)*
  - ✅ PostgreSQL parameter type handling (`$1::text` casting)
  - ✅ Event decoding pipeline from raw database rows
  - ✅ Error handling with detailed diagnostics
  - ✅ Integration with existing `event_log` for writes

- [x] **Comprehensive Testing**
  - ✅ SQL composition correctness (exact SQL verification)
  - ✅ Parameter adjustment across multiple facts
  - ✅ Complex SQL preservation (subqueries, CTEs)
  - ✅ **End-to-end database integration** (real events, real database)

### ✅ COMPLETED: Phase 2A - Fact Helpers & Event Appending  
- [x] **Create strongly-typed `ticket_facts_v2.gleam` helper functions**
  - ✅ Helper functions: `query_by_type_and_id`, `fold_into` for code reuse
  - ✅ All ticket facts: `exists`, `is_closed`, `current_assignee`, `priority`, `child_tickets`, `duplicate_status`, `all_child_tickets_closed`
  - ✅ Proper event ordering maintained (prepend + reverse pattern)
  - ✅ 4/4 tests passing with real database integration

- [x] **Update `facts_v2.gleam` to support appending events with facts-based consistency**
  - ✅ Added `QueryOperation` enum (`Read` vs `AppendConsistencyCheck`)
  - ✅ `compose_facts()` generates different SQL based on operation type
  - ✅ `append_events()` function with same API as event_log but uses facts for consistency
  - ✅ Proper conflict detection without string manipulation
  - ✅ 5/5 tests passing including append success/conflict scenarios

### 🔄 REMAINING: Phase 2B - Command Handler Migration
- [ ] Create `command_handler_v2.gleam` to support new fact-based approach  
- [ ] Migrate `assign_ticket_handler` to new system
- [ ] Migrate `close_ticket_handler` to new system
- [ ] Update all calling code to use new fact types
- [ ] Remove deprecated `event_filter.gleam`, `facts.gleam`, `event_log.gleam`, `command_handler.gleam` modules
- [ ] Remove v2 suffixes from all modules and types

### 📋 SESSION HANDOFF CONTEXT

**Key Accomplishments This Session:**
- Fixed critical event ordering bug in `facts_v2` (used inefficient `list.group` → custom fold with order preservation)
- Implemented clean SQL generation without string manipulation (operation types instead of replace)
- All event appending functionality working with proper conflict detection

**Files Modified:**
- `src/gleavent_sourced/customer_support/ticket_facts_v2.gleam` - Complete with helpers
- `src/gleavent_sourced/facts_v2.gleam` - Added append_events, QueryOperation  
- `test/gleavent_sourced/ticket_facts_v2_test.gleam` - 4 tests passing
- `test/gleavent_sourced/facts_v2_test.gleam` - 5 tests passing (including append test)

**Next Session Priority:**
1. Create `command_handler_v2.gleam` module
2. Migrate `assign_ticket_handler` to use `ticket_facts_v2` and `facts_v2.append_events`
3. Ensure optimistic concurrency control works end-to-end
