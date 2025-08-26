# Command Handler Architecture

## Overview

Our command handling system evolved from complex generic `CommandRouter` data structures to a simple pattern-matching dispatch approach.

## Architecture Pattern

### 1. Command Types (Centralized)
```gleam
// src/customer_support/ticket_commands.gleam
pub type OpenTicketCommand { ... }
pub type AssignTicketCommand { ... }
pub type CloseTicketCommand { ... }

pub type TicketError {
  ValidationError(message: String)
  BusinessRuleViolation(message: String)
}
```

### 2. Individual Handler Files
Each command gets its own handler file with a factory function:

```gleam
// src/customer_support/open_ticket_handler.gleam
pub fn create_open_ticket_handler() -> CommandHandler(...) {
  command_handler.CommandHandler(
    event_filter: event_filter_for_open_ticket,
    context_reducer: context_reducer_for_open_ticket,
    command_logic: command_logic_for_open_ticket,
    // ...
  )
}
```

### 3. Router with Pattern Matching
Simple dispatch function, no data structures:

```gleam
// src/customer_support/ticket_command_router.gleam
pub type TicketCommand {
  OpenTicket(OpenTicketCommand)
  AssignTicket(AssignTicketCommand) 
  CloseTicket(CloseTicketCommand)
}

pub fn handle_ticket_command(command: TicketCommand, db: pog.Connection) {
  case command {
    OpenTicket(cmd) -> {
      let handler = open_ticket_handler.create_open_ticket_handler()
      command_handler.execute(db, handler, cmd, 3)
    }
    // ... other commands
  }
}
```

## Key Benefits

1. **Type Safety**: Each handler has specific types, no generic unification
2. **Simplicity**: Direct function calls instead of wrapper objects
3. **Modularity**: Each handler in separate file with clear responsibility
4. **Framework Integration**: All handlers use same retry/conflict detection

## Handler Structure

Each handler should extract anonymous functions to module level:

```gleam
pub fn create_handler() -> CommandHandler(...) {
  CommandHandler(
    event_filter: event_filter_for_handler,
    context_reducer: context_reducer_for_handler, 
    command_logic: command_logic_for_handler,
    metadata_generator: metadata_generator_for_handler,
    // ...
  )
}

// Module-level functions for testability and readability
fn event_filter_for_handler(command: Command) -> EventFilter { ... }
fn context_reducer_for_handler(events: List(Event), initial: Context) -> Context { ... }
fn command_logic_for_handler(command: Command, context: Context) -> Result(...) { ... }
```

## File Organization

```
src/customer_support/
├── ticket_commands.gleam          # Command types and errors
├── ticket_command_router.gleam    # Pattern matching dispatch  
├── open_ticket_handler.gleam      # OpenTicket handler
├── assign_ticket_handler.gleam    # AssignTicket handler
└── close_ticket_handler.gleam     # CloseTicket handler
```

## Integration

The framework handles all complex concerns:
- Event loading and context building
- Optimistic concurrency control  
- Automatic retry on conflicts
- Event persistence

Handlers focus purely on business logic.