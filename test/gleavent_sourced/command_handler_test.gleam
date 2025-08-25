
import gleavent_sourced/command_handler
import gleavent_sourced/event_filter
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
