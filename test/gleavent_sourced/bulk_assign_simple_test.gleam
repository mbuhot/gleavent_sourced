import gleam/dict
import gleam/list
import gleavent_sourced/command_handler.{CommandAccepted}
import gleavent_sourced/customer_support/bulk_assign_handler
import gleavent_sourced/customer_support/ticket_commands.{
  BulkAssignCommand,
}
import gleavent_sourced/customer_support/ticket_events.{
  TicketAssigned, TicketOpened,
}
import gleavent_sourced/facts
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit([
    "gleavent_sourced/bulk_assign_simple_test",
  ])
}

// Helper function to create test metadata
fn create_test_metadata() {
  dict.new()
}

// Helper function to persist initial events for tests
fn setup_initial_events(db, events) {
  let test_metadata = create_test_metadata()
  let assert Ok(_) =
    facts.append_events(
      db,
      events,
      ticket_events.encode,
      test_metadata,
      [],
      0,
    )
}

pub fn bulk_assign_empty_list_test() {
  test_runner.txn(fn(db) {
    // Test with empty ticket list - should work with no parameters
    let command =
      BulkAssignCommand(
        [],
        // Empty list
        "alice@example.com",
        "2024-01-01T10:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed with empty events
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful execution with no events
    let assert CommandAccepted(events) = result
    assert events == []
  })
}

pub fn bulk_assign_single_ticket_test() {
  test_runner.txn(fn(db) {
    // Setup: Create one ticket
    let initial_events = [
      TicketOpened("T-100", "Single bug", "Just one ticket", "medium"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Test with single ticket
    let command =
      BulkAssignCommand(
        ["T-100"],
        // Single ticket
        "alice@example.com",
        "2024-01-01T10:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify result
    let assert CommandAccepted(events) = result
    let assert [
      TicketAssigned("T-100", "alice@example.com", "2024-01-01T10:00:00Z"),
    ] = events
  })
}

pub fn bulk_assign_two_tickets_test() {
  test_runner.txn(fn(db) {
    // Setup: Create two tickets
    let initial_events = [
      TicketOpened("T-200", "First bug", "First ticket", "high"),
      TicketOpened("T-201", "Second bug", "Second ticket", "low"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Test with two tickets
    let command =
      BulkAssignCommand(
        ["T-200", "T-201"],
        // Two tickets
        "bob@example.com",
        "2024-01-01T11:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify result
    let assert CommandAccepted(events) = result
    assert list.length(events) == 2
    let assert [
      TicketAssigned("T-200", "bob@example.com", "2024-01-01T11:00:00Z"),
      TicketAssigned("T-201", "bob@example.com", "2024-01-01T11:00:00Z"),
    ] = events
  })
}
