import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}

import gleavent_sourced/command_handler.{
  CommandAccepted, CommandRejected,
}
import gleavent_sourced/customer_support/ticket_command_router
import gleavent_sourced/customer_support/ticket_command_types
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

pub type ValidationError {
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
  assert initial_context == TicketContext(existing_tickets: [])

  // Test command logic with valid input
  let valid_command = OpenTicket("T-001", "Test ticket")
  let context = TicketContext(existing_tickets: [])
  let assert Ok(events) = handler.command_logic(valid_command, context)
  let assert [TicketOpened("T-001", "Test ticket")] = events

  // Test command logic with invalid input
  let invalid_command = OpenTicket("T-002", "")
  let assert Error(ValidationError(message)) =
    handler.command_logic(invalid_command, context)
  assert message == "Title cannot be empty"
}

pub fn command_rejection_scenarios_test() {
  test_runner.txn(fn(db) {
    // Test command rejection with empty title
    let empty_title_command =
      ticket_command_router.OpenTicket(ticket_command_types.OpenTicketCommand(
        "T-001",
        "",
        "Description",
        "medium",
      ))
    let assert Ok(result) =
      ticket_command_router.handle_ticket_command(empty_title_command, db)

    case result {
      CommandRejected(ticket_command_types.ValidationError(message)) -> {
        assert message == "Title cannot be empty"
      }
      _ -> panic as "Expected CommandRejected for empty title"
    }

    // Test command rejection with invalid priority
    let invalid_priority_command =
      ticket_command_router.OpenTicket(ticket_command_types.OpenTicketCommand(
        "T-002",
        "Valid title",
        "Description",
        "invalid",
      ))
    let assert Ok(result) =
      ticket_command_router.handle_ticket_command(invalid_priority_command, db)

    case result {
      CommandRejected(ticket_command_types.ValidationError(message)) -> {
        assert message == "Priority must be one of: low, medium, high, critical"
      }
      _ -> panic as "Expected CommandRejected for invalid priority"
    }
  })
}

pub fn context_building_with_assign_ticket_test() {
  test_runner.txn(fn(db) {
    // Create an initial ticket
    let create_command =
      ticket_command_router.OpenTicket(ticket_command_types.OpenTicketCommand(
        "T-001",
        "Initial ticket",
        "Test ticket",
        "medium",
      ))
    let assert Ok(CommandAccepted(_events)) =
      ticket_command_router.handle_ticket_command(create_command, db)

    // Test that assignment works with proper context building
    let assign_command =
      ticket_command_router.AssignTicket(
        ticket_command_types.AssignTicketCommand(
          "T-001",
          "alice@example.com",
          "2024-01-01T10:00:00Z",
        ),
      )
    let assert Ok(CommandAccepted(events)) =
      ticket_command_router.handle_ticket_command(assign_command, db)
    let assert [
      ticket_event.TicketAssigned(
        "T-001",
        "alice@example.com",
        "2024-01-01T10:00:00Z",
      ),
    ] = events

    // Test that context building prevents double assignment
    let double_assign_command =
      ticket_command_router.AssignTicket(
        ticket_command_types.AssignTicketCommand(
          "T-001",
          "bob@example.com",
          "2024-01-01T11:00:00Z",
        ),
      )
    let assert Ok(CommandRejected(ticket_command_types.BusinessRuleViolation(
      message,
    ))) = ticket_command_router.handle_ticket_command(double_assign_command, db)
    assert message == "Ticket already assigned to alice@example.com"
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
    let assert Ok(CommandAccepted(events)) =
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
    let assert Ok(CommandRejected(ticket_command_types.ValidationError(message))) =
      ticket_command_router.handle_ticket_command(empty_title_command, db)
    assert message == "Title cannot be empty"

    // Test invalid priority
    let invalid_priority_command =
      ticket_command_router.OpenTicket(ticket_command_types.OpenTicketCommand(
        "T-502",
        "Test ticket",
        "Description",
        "urgent",
      ))
    let assert Ok(CommandRejected(ticket_command_types.ValidationError(message))) =
      ticket_command_router.handle_ticket_command(invalid_priority_command, db)
    assert message == "Priority must be one of: low, medium, high, critical"
  })
}

pub fn assign_ticket_handler_with_context_building_test() {
  test_runner.txn(fn(db) {
    // First, create some initial ticket events
    let initial_events = [
      ticket_event.TicketOpened(
        ticket_id: "T-200",
        title: "Bug in payment system",
        description: "Payment processing fails",
        priority: "high",
      ),
      ticket_event.TicketOpened(
        ticket_id: "T-201",
        title: "UI improvement request",
        description: "Make buttons prettier",
        priority: "low",
      ),
    ]

    let test_metadata = ticket_event.create_test_metadata()
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        initial_events,
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Test successful assignment to unassigned ticket
    let assign_command =
      ticket_command_router.AssignTicket(
        ticket_command_types.AssignTicketCommand(
          "T-200",
          "alice@example.com",
          "2024-01-01T10:00:00Z",
        ),
      )

    let assert Ok(CommandAccepted(events)) =
      ticket_command_router.handle_ticket_command(assign_command, db)
    let assert [
      ticket_event.TicketAssigned(
        "T-200",
        "alice@example.com",
        "2024-01-01T10:00:00Z",
      ),
    ] = events

    // Test assignment to already assigned ticket (should fail)
    let double_assign_command =
      ticket_command_router.AssignTicket(
        ticket_command_types.AssignTicketCommand(
          "T-200",
          "bob@example.com",
          "2024-01-01T11:00:00Z",
        ),
      )

    let assert Ok(CommandRejected(ticket_command_types.BusinessRuleViolation(
      message,
    ))) = ticket_command_router.handle_ticket_command(double_assign_command, db)
    assert message == "Ticket already assigned to alice@example.com"

    // Test assignment to non-existent ticket (should fail)
    let missing_ticket_command =
      ticket_command_router.AssignTicket(
        ticket_command_types.AssignTicketCommand(
          "T-999",
          "charlie@example.com",
          "2024-01-01T12:00:00Z",
        ),
      )

    let assert Ok(CommandRejected(ticket_command_types.BusinessRuleViolation(
      message,
    ))) =
      ticket_command_router.handle_ticket_command(missing_ticket_command, db)
    assert message == "Ticket does not exist"
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

    let assert Ok(CommandRejected(ValidationError(message))) =
      command_handler.handle_with_retry(
        db,
        conflicting_handler,
        test_command,
        3,
      )
    assert message == "Ticket already assigned to concurrent_user@example.com"
  })
}
