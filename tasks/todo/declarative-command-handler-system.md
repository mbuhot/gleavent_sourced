# Declarative Command Handler System

## Requirement
Create a declarative command handler system that automates the boilerplate of event sourcing command processing, allowing developers to focus on business logic while the system handles event loading, conflict detection, and retry logic.

## Design

### Core Types
```gleam
// Generic command handler definition
pub type CommandHandler(command, event, context, error) {
  CommandHandler(
    event_filter: fn(command) -> EventFilter,
    context_reducer: fn(List(event), context) -> context,
    initial_context: context,
    command_logic: fn(command, context) -> Result(List(event), error),
  )
}

// Command processing result
pub type CommandResult(event, error) {
  CommandAccepted(events: List(event))
  CommandRejected(error: error)
  CommandFailed(system_error: String)
}

// Command router for dispatching
pub type CommandRouter(command, event, error) {
  CommandRouter(handlers: Dict(String, CommandHandler))
}
```

### Handler Registration & Dispatch
```gleam
pub fn register_handler(
  router: CommandRouter,
  command_type: String,
  handler: CommandHandler,
) -> CommandRouter

pub fn handle_command(
  router: CommandRouter,
  db: pog.Connection,
  command_type: String,
  command: command,
) -> Result(CommandResult, String)
```

### Internal Processing Flow
1. **Dispatch**: Route command to appropriate handler based on command type
2. **Context Building**: Use handler's event_filter to load relevant events
3. **Context Reduction**: Fold loaded events into context using context_reducer
4. **Decision Logic**: Apply command_logic(command, context) → Result(List(event), error)
5. **Event Persistence**: If accepted, append events with conflict detection
6. **Retry on Conflict**: On optimistic concurrency conflict, repeat from step 2
7. **Return Result**: CommandAccepted/CommandRejected/CommandFailed

### Conflict Handling Strategy
- **Automatic Retry**: System automatically retries on optimistic concurrency conflicts
- **Max Retries**: Configurable retry limit (default: 3)
- **Fresh Context**: Each retry rebuilds context from current event state
- **Deterministic Logic**: Same command + context should always produce same result

## Task Breakdown (TDD Approach)

### 1. Command Handler Types and Basic Structure
- [ ] Create `CommandHandler`, `CommandResult`, and `CommandRouter` types with `todo` stubs
- [ ] Write test for command handler type creation and basic structure
- [ ] Implement type constructors and basic functionality
- [ ] Write test for command router registration and lookup
- [ ] Implement command router registration (`register_handler`, lookup functions)

### 2. Simple Command Processing (No Conflicts)
- [ ] Create stub for `handle_command` function with `todo`
- [ ] Write test for successful command processing (OpenTicket example)
- [ ] Implement basic command processing flow: filter → query → reduce → logic → append
- [ ] Write test for command rejection scenarios
- [ ] Implement command rejection handling and error propagation

### 3. Event Integration and Context Building
- [ ] Write test for event loading using EventFilter from command
- [ ] Implement integration with `event_log.query_events` for context building
- [ ] Write test for context reduction from loaded events
- [ ] Implement context reducer application and state building

### 4. Optimistic Concurrency and Retry Logic
- [ ] Write test for conflict detection and automatic retry
- [ ] Implement `AppendConflict` handling with retry mechanism
- [ ] Write test for max retry limits and failure scenarios
- [ ] Implement retry loop with fresh context rebuilding

### 5. Complete Ticket System Examples

#### Basic Ticket Operations
- [ ] Write tests for OpenTicket command (simple case, no event loading needed)
- [ ] Implement OpenTicket handler with title validation

#### Complex Event Filtering and Context Building
- [ ] Write test for AssignTicket command that:
  - Filters events by `ticket_id` extracted from command
  - Loads `TicketOpened`, `TicketAssigned`, `TicketClosed` events for that ticket
  - Reduces events into `TicketState{status, current_assignee, created_at}`
  - Validates ticket exists and is not already closed
  - Prevents double-assignment to same person
- [ ] Implement AssignTicket handler with complex event filter and context reducer

#### Advanced Business Logic with State
- [ ] Write test for CloseTicket command that:
  - Builds full ticket context from event history
  - Ensures ticket is in "open" or "assigned" status
  - Requires resolution text based on ticket priority
  - Validates closer has appropriate permissions (based on assignee)
- [ ] Implement CloseTicket handler with stateful business rules

#### Conflict Detection Scenarios
- [ ] Write test for concurrent assignment attempts (optimistic concurrency)
- [ ] Write test for closing already-closed tickets
- [ ] Write test for assigning non-existent tickets
- [ ] Implement proper error handling and conflict retry logic


## Example Usage

### Simple Case: OpenTicket (No Event Loading)
```gleam
let open_ticket_handler = CommandHandler(
  event_filter: fn(_command) { event_filter.new() }, // No conflicts for new tickets
  context_reducer: fn(_events, initial) { initial }, // Simple passthrough
  initial_context: [],
  command_logic: fn(command, _context) {
    case command.title {
      "" -> Error("Title cannot be empty")
      _ -> Ok([TicketOpened(
        ticket_id: command.ticket_id,
        title: command.title,
        description: command.description,
        priority: command.priority,
      )])
    }
  },
)
```

### Complex Case: AssignTicket (Event Loading & Context Building)
```gleam
pub type TicketState {
  TicketState(
    status: TicketStatus,
    current_assignee: Option(String),
    created_at: String,
    priority: String,
  )
}

let assign_ticket_handler = CommandHandler(
  event_filter: fn(command) {
    // Filter events for specific ticket using command parameter
    event_filter.new()
    |> event_filter.for_type("TicketOpened", [
      event_filter.attr_string("ticket_id", command.ticket_id),
    ])
    |> event_filter.for_type("TicketAssigned", [
      event_filter.attr_string("ticket_id", command.ticket_id),
    ])
    |> event_filter.for_type("TicketClosed", [
      event_filter.attr_string("ticket_id", command.ticket_id),
    ])
  },
  context_reducer: fn(events, initial_state) {
    // Fold events to build current ticket state
    list.fold(events, initial_state, fn(state, event) {
      case event {
        TicketOpened(ticket_id, .., created_at, priority) ->
          TicketState(Open, None, created_at, priority)
        TicketAssigned(_, assignee, _) ->
          TicketState(..state, status: Assigned, current_assignee: Some(assignee))
        TicketClosed(..) ->
          TicketState(..state, status: Closed)
      }
    })
  },
  initial_context: TicketState(NotFound, None, "", ""),
  command_logic: fn(command, ticket_state) {
    case ticket_state.status {
      NotFound -> Error("Ticket does not exist")
      Closed -> Error("Cannot assign closed ticket")
      _ -> case ticket_state.current_assignee {
        Some(assignee) if assignee == command.assignee ->
          Error("Ticket already assigned to " <> assignee)
        _ -> Ok([TicketAssigned(
          ticket_id: command.ticket_id,
          assignee: command.assignee,
          assigned_at: command.assigned_at,
        )])
      }
    }
  },
)

// Register handlers
let router = command_router.new()
  |> command_router.register_handler("OpenTicket", open_ticket_handler)
  |> command_router.register_handler("AssignTicket", assign_ticket_handler)

// Process commands
let result = command_router.handle_command(
  router,
  db,
  "AssignTicket",
  AssignTicketCommand(
    ticket_id: "T-001", 
    assignee: "john.doe@example.com",
    assigned_at: "2024-01-15T10:30:00Z",
  ),
)
```

## Notes

- This system should be built on top of our existing `event_log` and `event_filter` modules
- Consider using Gleam's type system to ensure compile-time safety
- The system should be opinionated but extensible
- Focus on common patterns first, advanced features later
- Document performance implications of different event filter strategies
