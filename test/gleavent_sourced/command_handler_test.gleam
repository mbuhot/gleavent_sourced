import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleavent_sourced/command_handler
import gleavent_sourced/customer_support/ticket_command_router
import gleavent_sourced/customer_support/ticket_command_types
import gleavent_sourced/customer_support/ticket_event
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/test_runner
import pog

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
  let handler =
    command_handler.CommandHandler(
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
      event_mapper: fn(_event_type, _payload) {
        Error("No events expected in this test")
      },
      event_converter: fn(_event) { #("TestEvent", json.string("test")) },
      metadata_generator: fn(_command, _context) { dict.new() },
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
  let assert Error(ValidationError(message)) =
    handler.command_logic(invalid_command, context)
  let assert "Title cannot be empty" = message
}

pub fn command_router_creation_and_registration_test() {
  test_runner.txn(fn(db) {
    // Create a new router
    let router = command_handler.new()

    // Create a test handler
    let handler =
      command_handler.CommandHandler(
        event_filter: fn(_command) { event_filter.new() },
        context_reducer: fn(_events, context) { context },
        initial_context: TicketContext(existing_tickets: []),
        command_logic: fn(command, _context) {
          case command {
            OpenTicket(ticket_id, title) -> Ok([TicketOpened(ticket_id, title)])
          }
        },
        event_mapper: fn(_event_type, _payload) {
          Error("No events expected in this test")
        },
        event_converter: fn(_event) { #("TestEvent", json.string("test")) },
        metadata_generator: fn(_command, _context) { dict.new() },
      )

    // Register the handler
    let updated_router =
      command_handler.register_handler(router, "OpenTicket", handler)

    // Test behavior: dispatch a command through the registered handler
    // This will fail until we implement handle_command
    let test_command = OpenTicket("T-001", "Test registration")
    let assert Ok(command_handler.CommandAccepted(events)) =
      command_handler.handle_command(
        updated_router,
        db,
        "OpenTicket",
        test_command,
      )

    // Verify the handler executed its business logic correctly
    let assert [TicketOpened("T-001", "Test registration")] = events
  })
}

pub fn command_rejection_scenarios_test() {
  test_runner.txn(fn(db) {
    // Create a router with a handler that validates commands
    let router = command_handler.new()

    let validating_handler =
      command_handler.CommandHandler(
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
        event_mapper: fn(_event_type, _payload) {
          Error("No events expected in this test")
        },
        event_converter: fn(_event) { #("TestEvent", json.string("test")) },
        metadata_generator: fn(_command, _context) { dict.new() },
      )

    let updated_router =
      command_handler.register_handler(router, "OpenTicket", validating_handler)

    // Test command rejection with empty title
    let empty_title_command = OpenTicket("T-001", "")
    let assert Ok(command_handler.CommandRejected(ValidationError(message))) =
      command_handler.handle_command(
        updated_router,
        db,
        "OpenTicket",
        empty_title_command,
      )
    let assert "Title cannot be empty" = message

    // Test command rejection with forbidden title
    let forbidden_command = OpenTicket("T-002", "forbidden")
    let assert Ok(command_handler.CommandRejected(ValidationError(message))) =
      command_handler.handle_command(
        updated_router,
        db,
        "OpenTicket",
        forbidden_command,
      )
    let assert "Forbidden title" = message

    // Test unknown command type
    let unknown_result =
      command_handler.handle_command(
        updated_router,
        db,
        "UnknownCommand",
        OpenTicket("T-003", "test"),
      )
    let assert Error(error_message) = unknown_result
    let assert "Handler not found for command type: UnknownCommand" =
      error_message
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
        priority: "medium",
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
    let context_building_handler =
      command_handler.CommandHandler(
        event_filter: fn(command) {
          // Create filter based on command - this will load events for specific ticket
          case command {
            ticket_command_types.OpenTicketCommand(ticket_id, _, _, _) -> {
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
            ticket_command_types.OpenTicketCommand(
              ticket_id,
              title,
              description,
              priority,
            ) -> {
              // Business logic that depends on context: prevent duplicate ticket IDs
              case list.length(context.existing_tickets) {
                0 ->
                  Ok([
                    ticket_event.TicketOpened(
                      ticket_id,
                      title,
                      description,
                      priority,
                    ),
                  ])
                _ ->
                  Error(ValidationError(
                    "Ticket ID already exists: " <> ticket_id,
                  ))
              }
            }
          }
        },
        event_mapper: ticket_event.ticket_event_mapper,
        event_converter: ticket_event.ticket_event_to_type_and_payload,
        metadata_generator: fn(_command, _context) {
          ticket_event.create_test_metadata()
        },
      )

    let router =
      command_handler.new()
      |> command_handler.register_handler(
        "OpenTicketCommand",
        context_building_handler,
      )

    // This should fail because T-001 already exists (based on loaded events)
    let duplicate_command =
      ticket_command_types.OpenTicketCommand(
        "T-001",
        "Duplicate ticket",
        "This should fail",
        "low",
      )
    let result =
      command_handler.handle_command(
        router,
        db,
        "OpenTicketCommand",
        duplicate_command,
      )

    // This assertion will fail until we implement event loading
    let assert Ok(command_handler.CommandRejected(ValidationError(message))) =
      result
    let assert "Ticket ID already exists: T-001" = message
  })
}

pub fn open_ticket_command_validation_test() {
  test_runner.txn(fn(db) {
    // Test successful ticket creation
    let valid_command =
      ticket_command_router.OpenTicket(ticket_command_types.OpenTicketCommand(
        "T-500",
        "Fix login bug",
        "Users cannot login",
        "high",
      ))
    let assert Ok(command_handler.CommandAccepted(events)) =
      ticket_command_router.handle_ticket_command(valid_command, db)
    let assert [
      ticket_event.TicketOpened(
        "T-500",
        "Fix login bug",
        "Users cannot login",
        "high",
      ),
    ] = events

    // Test validation errors
    let empty_title_command =
      ticket_command_router.OpenTicket(ticket_command_types.OpenTicketCommand(
        "T-501",
        "",
        "Description",
        "medium",
      ))
    let assert Ok(command_handler.CommandRejected(ticket_command_types.ValidationError(
      message,
    ))) = ticket_command_router.handle_ticket_command(empty_title_command, db)
    let assert "Title cannot be empty" = message

    // Test invalid priority
    let invalid_priority_command =
      ticket_command_router.OpenTicket(ticket_command_types.OpenTicketCommand(
        "T-502",
        "Test ticket",
        "Description",
        "urgent",
      ))
    let assert Ok(command_handler.CommandRejected(ticket_command_types.ValidationError(
      message,
    ))) =
      ticket_command_router.handle_ticket_command(invalid_priority_command, db)
    let assert "Priority must be one of: low, medium, high, critical" = message
  })
}

pub fn optimistic_concurrency_conflict_detection_test() {
  test_runner.txn(fn(db) {
    // Store initial event to establish baseline
    let initial_event =
      ticket_event.TicketOpened(
        ticket_id: "T-100",
        title: "Initial ticket",
        description: "Test ticket for concurrency",
        priority: "medium",
      )

    let test_metadata = ticket_event.create_test_metadata()
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        [initial_event],
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Create a handler that breaks convention by inserting event during business logic
    let conflicting_handler =
      command_handler.CommandHandler(
        event_filter: fn(command) {
          case command {
            ticket_command_types.AssignTicketCommand(ticket_id, _, _) -> {
              event_filter.new()
              |> event_filter.for_type("TicketOpened", [
                event_filter.attr_string("ticket_id", ticket_id),
              ])
              |> event_filter.for_type("TicketAssigned", [
                event_filter.attr_string("ticket_id", ticket_id),
              ])
            }
          }
        },
        context_reducer: fn(events, _initial) {
          list.fold(events, None, fn(current_assignee, event) {
            case event {
              ticket_event.TicketAssigned(_, assignee, _) -> Some(assignee)
              _ -> current_assignee
            }
          })
        },
        initial_context: None,
        command_logic: fn(command, current_assignee) {
          case command {
            ticket_command_types.AssignTicketCommand(
              ticket_id,
              assignee,
              assigned_at,
            ) -> {
              case current_assignee {
                Some(existing) ->
                  Error(ValidationError(
                    "Ticket already assigned to " <> existing,
                  ))
                None -> {
                  // BREAK CONVENTION: Insert conflicting event during business logic!
                  // This simulates a race condition where another process inserts an event
                  // between when we loaded context and when we try to append our events
                  let conflicting_assignment =
                    ticket_event.TicketAssigned(
                      ticket_id,
                      "concurrent_user@example.com",
                      "2024-01-01T09:59:00Z",
                    )

                  let assert Ok(event_log.AppendSuccess) =
                    event_log.append_events(
                      db,
                      [conflicting_assignment],
                      ticket_event.ticket_event_to_type_and_payload,
                      test_metadata,
                      event_filter.new(),
                      // No conflict check
                      0,
                    )

                  // Return our events - this should cause conflict detection!
                  Ok([
                    ticket_event.TicketAssigned(
                      ticket_id,
                      assignee,
                      assigned_at,
                    ),
                  ])
                }
              }
            }
          }
        },
        event_mapper: ticket_event.ticket_event_mapper,
        event_converter: ticket_event.ticket_event_to_type_and_payload,
        metadata_generator: fn(_command, _context) {
          ticket_event.create_test_metadata()
        },
      )

    let router =
      command_handler.new()
      |> command_handler.register_handler("AssignTicket", conflicting_handler)

    // This command should:
    // 1. Load events (sees only TicketOpened)
    // 2. Execute business logic which inserts conflicting event
    // 3. Try to append its own events - CONFLICT DETECTED!
    // 4. Retry with fresh context
    // 5. See the conflicting assignment and reject the command
    let test_command =
      ticket_command_types.AssignTicketCommand(
        "T-100",
        "test_user@example.com",
        "2024-01-01T10:00:00Z",
      )

    let assert Ok(command_handler.CommandRejected(ValidationError(message))) =
      command_handler.handle_command(router, db, "AssignTicket", test_command)
    let assert "Ticket already assigned to concurrent_user@example.com" =
      message
  })
}
