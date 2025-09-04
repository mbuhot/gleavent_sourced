import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleavent_sourced/command_handler_v2.{CommandAccepted, CommandRejected}
import gleavent_sourced/customer_support/open_ticket_handler_v2
import gleavent_sourced/customer_support/ticket_commands.{
  OpenTicketCommand, ValidationError,
}
import gleavent_sourced/customer_support/ticket_events.{TicketOpened}
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit([
    "gleavent_sourced/open_ticket_handler_v2_test",
  ])
}

// Helper function to create test metadata
fn create_test_metadata() {
  dict.new()
}

pub fn successful_ticket_creation_test() {
  test_runner.txn(fn(db) {
    // Create valid open ticket command
    let command =
      OpenTicketCommand(
        "T-100",
        "Bug in payment system",
        "Payment processing fails intermittently",
        "high",
        parent_ticket_id: None,
      )
    let handler = open_ticket_handler_v2.create_open_ticket_handler_v2()
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify successful creation
    let assert CommandAccepted(events) = result
    let assert [
      TicketOpened(
        "T-100",
        "Bug in payment system",
        "Payment processing fails intermittently",
        "high",
      ),
    ] = events
  })
}

pub fn empty_ticket_id_validation_fails_test() {
  test_runner.txn(fn(db) {
    // Create command with empty ticket ID
    let command =
      OpenTicketCommand(
        "",
        // Empty ticket ID
        "Valid title",
        "Valid description",
        "medium",
        parent_ticket_id: None,
      )
    let handler = open_ticket_handler_v2.create_open_ticket_handler_v2()
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(ValidationError(message)) = result
    assert message == "Ticket ID cannot be empty"
  })
}

pub fn empty_title_validation_fails_test() {
  test_runner.txn(fn(db) {
    // Create command with empty title
    let command =
      OpenTicketCommand(
        "T-101",
        "",
        // Empty title
        "Valid description",
        "low",
        parent_ticket_id: None,
      )
    let handler = open_ticket_handler_v2.create_open_ticket_handler_v2()
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(ValidationError(message)) = result
    assert message == "Title cannot be empty"
  })
}

pub fn title_too_long_validation_fails_test() {
  test_runner.txn(fn(db) {
    // Create command with title longer than 100 characters
    let long_title =
      "This is a very long title that exceeds the maximum allowed length of 100 characters and should be rejected by validation logic"
    let command =
      OpenTicketCommand(
        "T-102",
        long_title,
        // 125 characters - too long
        "Valid description",
        "critical",
        parent_ticket_id: None,
      )
    let handler = open_ticket_handler_v2.create_open_ticket_handler_v2()
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(ValidationError(message)) = result
    assert message == "Title cannot exceed 100 characters"
  })
}

pub fn invalid_priority_validation_fails_test() {
  test_runner.txn(fn(db) {
    // Create command with invalid priority
    let command =
      OpenTicketCommand(
        "T-103",
        "Valid title",
        "Valid description",
        "urgent",
        // Invalid priority - not in allowed list
        parent_ticket_id: None,
      )
    let handler = open_ticket_handler_v2.create_open_ticket_handler_v2()
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(ValidationError(message)) = result
    assert message == "Priority must be one of: low, medium, high, critical"
  })
}

pub fn all_valid_priorities_succeed_test() {
  test_runner.txn(fn(db) {
    let valid_priorities = ["low", "medium", "high", "critical"]
    let metadata = create_test_metadata()

    // Test each valid priority
    let _ =
      list.index_map(valid_priorities, fn(priority, index) {
        let ticket_id = "T-" <> int.to_string(200 + index)
        let command =
          OpenTicketCommand(
            ticket_id,
            "Test ticket with " <> priority <> " priority",
            "Testing valid priority values",
            priority,
            parent_ticket_id: None,
          )
        let handler = open_ticket_handler_v2.create_open_ticket_handler_v2()

        // Execute command - should succeed for all valid priorities
        let assert Ok(result) =
          command_handler_v2.execute(db, handler, command, metadata)
        let assert CommandAccepted(events) = result
        let assert [TicketOpened(ticket_id_result, _, _, priority_result)] =
          events
        assert ticket_id_result == ticket_id
        assert priority_result == priority
      })
  })
}
