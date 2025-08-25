import gleam/list
import gleavent_sourced/command_handler
import gleavent_sourced/customer_support/ticket_event
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/test_runner

// Example types for testing
pub type TestCommand {
  OpenTicket(ticket_id: String, title: String)
}

pub type TestEvent {
  TicketOpened(ticket_id: String, title: String)
}

pub type TestContext {
  TicketContext(existing_tickets: List(String))
}

pub type TestError {
  ValidationError(message: String)
}

pub type OpenTicketCommand {
  OpenTicketCommand(ticket_id: String, title: String, description: String, priority: String)
}

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/command_handler_test"])
}

pub fn command_handler_type_creation_test() {
  // Create a simple command handler
  let handler = command_handler.CommandHandler(
    event_filter: fn(_command) { event_filter.new() },
    context_reducer: fn(_events, context) { context },
    initial_context: TicketContext(existing_tickets: []),
    command_logic: fn(command, _context) {
      case command {
        OpenTicket(ticket_id, title) -> {
          case title {
            "" -> Error(ValidationError("Title cannot be empty"))
            _ -> Ok([TicketOpened(ticket_id, title)])
          }
        }
      }
    },
    event_mapper: fn(_event_type, _payload) { Error("No events expected in this test") },
  )

  // Test that the handler has the expected structure
  let initial_context = handler.initial_context
  let assert TicketContext(existing_tickets: []) = initial_context

  // Test command logic with valid input
  let valid_command = OpenTicket("T-001", "Test ticket")
  let context = TicketContext(existing_tickets: [])
  let assert Ok(events) = handler.command_logic(valid_command, context)
  let assert [TicketOpened("T-001", "Test ticket")] = events

  // Test command logic with invalid input
  let invalid_command = OpenTicket("T-002", "")
  let assert Error(ValidationError(message)) = handler.command_logic(invalid_command, context)
  let assert "Title cannot be empty" = message
}

pub fn command_router_creation_and_registration_test() {
  test_runner.txn(fn(db) {
    // Create a new router
    let router = command_handler.new()

    // Create a test handler
    let handler = command_handler.CommandHandler(
      event_filter: fn(_command) { event_filter.new() },
      context_reducer: fn(_events, context) { context },
      initial_context: TicketContext(existing_tickets: []),
      command_logic: fn(command, _context) {
        case command {
          OpenTicket(ticket_id, title) -> Ok([TicketOpened(ticket_id, title)])
        }
      },
      event_mapper: fn(_event_type, _payload) { Error("No events expected in this test") },
    )

    // Register the handler
    let updated_router = command_handler.register_handler(router, "OpenTicket", handler)

    // Test behavior: dispatch a command through the registered handler
    // This will fail until we implement handle_command
    let test_command = OpenTicket("T-001", "Test registration")
    let assert Ok(command_handler.CommandAccepted(events)) =
      command_handler.handle_command(updated_router, db, "OpenTicket", test_command)

    // Verify the handler executed its business logic correctly
    let assert [TicketOpened("T-001", "Test registration")] = events
  })
}

pub fn command_rejection_scenarios_test() {
  test_runner.txn(fn(db) {
    // Create a router with a handler that validates commands
    let router = command_handler.new()

    let validating_handler = command_handler.CommandHandler(
      event_filter: fn(_command) { event_filter.new() },
      context_reducer: fn(_events, context) { context },
      initial_context: TicketContext(existing_tickets: []),
      command_logic: fn(command, _context) {
        case command {
          OpenTicket(_ticket_id, title) -> {
            case title {
              "" -> Error(ValidationError("Title cannot be empty"))
              "forbidden" -> Error(ValidationError("Forbidden title"))
              _ -> Ok([TicketOpened("T-001", title)])
            }
          }
        }
      },
      event_mapper: fn(_event_type, _payload) { Error("No events expected in this test") },
    )

    let updated_router = command_handler.register_handler(router, "OpenTicket", validating_handler)

    // Test command rejection with empty title
    let empty_title_command = OpenTicket("T-001", "")
    let assert Ok(command_handler.CommandRejected(ValidationError(message))) =
      command_handler.handle_command(updated_router, db, "OpenTicket", empty_title_command)
    let assert "Title cannot be empty" = message

    // Test command rejection with forbidden title
    let forbidden_command = OpenTicket("T-002", "forbidden")
    let assert Ok(command_handler.CommandRejected(ValidationError(message))) =
      command_handler.handle_command(updated_router, db, "OpenTicket", forbidden_command)
    let assert "Forbidden title" = message

    // Test unknown command type
    let unknown_result = command_handler.handle_command(updated_router, db, "UnknownCommand", OpenTicket("T-003", "test"))
    let assert Error(error_message) = unknown_result
    let assert "Handler not found for command type: UnknownCommand" = error_message
  })
}

pub fn event_loading_and_context_building_test() {
  test_runner.txn(fn(db) {
    // First, store some events in the database that our command handler will need to load
    let existing_events = [
      ticket_event.TicketOpened(
        ticket_id: "T-001",
        title: "First ticket",
        description: "Existing ticket",
        priority: "medium"
      ),
    ]

    // Store these events in the database
    let test_metadata = ticket_event.create_test_metadata()
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        existing_events,
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Create a command handler that loads events based on command parameters
    let context_building_handler = command_handler.CommandHandler(
      event_filter: fn(command) {
        // Create filter based on command - this will load events for specific ticket
        case command {
          OpenTicketCommand(ticket_id, _, _, _) -> {
            event_filter.new()
            |> event_filter.for_type("TicketOpened", [
              event_filter.attr_string("ticket_id", ticket_id),
            ])
          }
        }
      },
      context_reducer: fn(events, _initial) {
        // Build context from loaded events - count existing tickets with this ID
        let ticket_count = list.length(events)
        TicketContext(existing_tickets: list.repeat("existing", ticket_count))
      },
      initial_context: TicketContext(existing_tickets: []),
      command_logic: fn(command, context) {
        case command {
          OpenTicketCommand(ticket_id, title, description, priority) -> {
            // Business logic that depends on context: prevent duplicate ticket IDs
            case list.length(context.existing_tickets) {
              0 -> Ok([ticket_event.TicketOpened(ticket_id, title, description, priority)])
              _ -> Error(ValidationError("Ticket ID already exists: " <> ticket_id))
            }
          }
        }
      },
      event_mapper: ticket_event.ticket_event_mapper,
    )

    let router = command_handler.new()
      |> command_handler.register_handler("OpenTicketCommand", context_building_handler)

    // This should fail because T-001 already exists (based on loaded events)
    let duplicate_command = OpenTicketCommand("T-001", "Duplicate ticket", "This should fail", "low")
    let result = command_handler.handle_command(router, db, "OpenTicketCommand", duplicate_command)

    // This assertion will fail until we implement event loading
    let assert Ok(command_handler.CommandRejected(ValidationError(message))) = result
    let assert "Ticket ID already exists: T-001" = message
  })
}
