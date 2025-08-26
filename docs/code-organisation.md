# Code Organisation with Bounded Contexts

This document covers how to organize code using Domain-Driven Design bounded contexts in a Gleam event-sourced application.

## Overview

Instead of organizing code by technical layers (controllers, services, repositories), we organize by business domains (bounded contexts). Each bounded context encapsulates its own events, commands, queries, and business logic.

## Directory Structure

```
src/
└── gleavent_sourced/              # Project root
    ├── sql/
    │   └── events.sql             # Core event store operations
    ├── sql.gleam                  # Generated SQL functions (all contexts)
    ├── event_log.gleam            # Event persistence helpers
    ├── events.gleam               # Event decoding utilities
    ├── connection_pool.gleam      # Database connection management
    ├── parrot_pog.gleam          # Parrot-Pog integration utilities
    │
    └── customer_support/          # Bounded context for customer support
        ├── sql/
        │   └── tickets.sql        # Business-specific ticket queries
        ├── ticket_event.gleam     # Domain events for tickets
        ├── ticket_command.gleam   # Commands (future)
        ├── create_ticket_handler.gleam # Command handlers (future)
        ├── assign_ticket_handler.gleam
        └── close_ticket_handler.gleam
```

## Bounded Context Principles

### 1. Domain Encapsulation
Each bounded context contains everything related to a specific business domain:
- **Events**: Domain-specific event types and their JSON serialization
- **Commands**: Operations that can be performed in the domain
- **Handlers**: Business logic for processing commands and producing events
- **Queries**: SQL queries optimized for the domain's read patterns

### 2. Shared Infrastructure
Core event sourcing infrastructure is shared across all bounded contexts:
- Event storage and retrieval
- Database connection pooling
- Common utilities for event handling

### 3. Generated Code Consolidation
Parrot generates a single `sql.gleam` file containing functions from all bounded contexts, providing type-safe access to all queries across the application.

## Parrot Integration

### SQL File Discovery
Parrot automatically discovers SQL files by scanning for any directory named `sql` under `src/`:

```
src/gleavent_sourced/
├── sql/events.sql                         # ✓ Found
├── customer_support/sql/tickets.sql       # ✓ Found  
├── billing/sql/invoices.sql               # ✓ Found
└── analytics/sql/reports.sql              # ✓ Found
```

### Generated Output
All SQL functions are consolidated into a single `src/gleavent_sourced/sql.gleam`:

```gleam
// From events.sql
pub fn append_event(...)
pub fn read_all_events()
pub fn read_events_by_types(...)

// From tickets.sql  
pub fn read_events_for_ticket_command_context(...)

// From invoices.sql
pub fn read_billing_events_for_customer(...)
```

## Example: Customer Support Bounded Context

### Domain Events (`gleavent_sourced/customer_support/ticket_events.gleam`)

```gleam
pub type TicketEvent {
  TicketOpened(
    ticket_id: String,
    title: String, 
    description: String,
    priority: String,
  )
  TicketAssigned(ticket_id: String, assignee: String, assigned_at: String)
  TicketClosed(ticket_id: String, resolution: String, closed_at: String)
}

pub fn ticket_event_to_type_and_payload(event: TicketEvent) -> #(String, json.Json) {
  case event {
    TicketOpened(ticket_id, title, description, priority) -> {
      let payload = json.object([
        #("ticket_id", json.string(ticket_id)),
        #("title", json.string(title)),
        #("description", json.string(description)),
        #("priority", json.string(priority)),
      ])
      #("TicketOpened", payload)
    }
    // ... other event types
  }
}
```

### Domain Queries (`gleavent_sourced/customer_support/sql/tickets.sql`)

```sql
-- name: ReadEventsForTicketCommandContext :many
SELECT sequence_number, occurred_at, event_type, payload, metadata
FROM events
WHERE (event_type = 'TicketOpened' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketAssigned' AND payload->>'ticket_id' = @ticket_id)
   OR (event_type = 'TicketClosed' AND payload->>'ticket_id' = @ticket_id)
ORDER BY sequence_number;
```

### Command Handlers (Future)

```gleam
// customer_support/create_ticket_handler.gleam
pub fn handle_create_ticket(command: CreateTicket) -> Result(List(TicketEvent), BusinessError) {
  // 1. Load existing events for validation
  // 2. Apply business rules
  // 3. Return new events to append
}
```

## Benefits of This Organization

### 1. Clear Domain Boundaries
- Each bounded context has clear responsibility
- Business logic is encapsulated within domains
- Reduces coupling between different business areas

### 2. Independent Evolution
- Each bounded context can evolve independently
- Different domains can use different patterns as needed
- Team ownership aligns with business domains

### 3. Optimized Queries
- Each domain defines queries optimized for its specific needs
- No need to create generic queries that work for all domains
- Better performance through targeted indexing

### 4. Type Safety Across Domains
- Parrot generates type-safe functions for all domains
- Compile-time checking prevents query errors
- Consistent parameter binding across all contexts

## Naming Conventions

### Files
- Use snake_case for file names
- Singular domain names: `ticket_event.gleam`, not `tickets_events.gleam`
- Descriptive suffixes: `_event.gleam`, `_command.gleam`, `_handler.gleam`

### SQL Queries
- Use PascalCase for query names in comments: `ReadEventsForTicketCommandContext`
- Describe the business purpose, not technical implementation
- Group related queries in the same SQL file

### Functions
- Generated functions use snake_case: `read_events_for_ticket_command_context()`
- Parameters use labeled arguments: `ticket_id: String`

## Anti-Patterns to Avoid

### ❌ Technical Layers
```
src/
├── controllers/
├── services/
├── repositories/
└── models/
```

### ❌ Shared Domain Objects
```gleam
// Don't create shared domain types across contexts
pub type GenericEvent {
  UserEvent(...)
  TicketEvent(...)
  BillingEvent(...)
}
```

### ❌ Cross-Context Dependencies
```gleam
// Don't import domain types from other contexts
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/billing/invoice_event

// In user_registration_handler.gleam - BAD!
```

## Testing Organization

Tests should mirror the bounded context structure:

```
test/
├── gleavent_sourced/
│   └── ticket_events_test.gleam     # Tests the customer_support domain
├── integration/
│   └── end_to_end_test.gleam        # Cross-domain integration tests
└── gleavent_sourced/
    └── customer_support/
    ├── ticket_command_test.gleam     # Unit tests for domain logic
    └── ticket_handler_test.gleam
```

## Migration Strategy

### From Layered Architecture
1. **Identify Domains**: Group related functionality by business capability
2. **Create Bounded Contexts**: Create directories under `src/gleavent_sourced/`
3. **Separate SQL**: Move domain-specific queries to context SQL directories
4. **Regenerate**: Run Parrot to update generated SQL functions
5. **Update Imports**: Fix import statements to reference new locations

### Adding New Bounded Contexts
1. Create new directory under `src/gleavent_sourced/`
2. Add `sql/` subdirectory with domain queries
3. Create domain event types and converters
4. Run Parrot to generate new SQL functions
5. Write tests to verify the domain works correctly

This organization provides a solid foundation for building complex event-sourced systems that can grow and evolve with changing business requirements.