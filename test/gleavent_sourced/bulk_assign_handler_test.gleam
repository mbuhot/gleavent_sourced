import gleam/dict
import gleam/list
import gleavent_sourced/command_handler.{CommandAccepted, CommandRejected}
import gleavent_sourced/customer_support/bulk_assign_handler
import gleavent_sourced/customer_support/ticket_commands.{
  BulkAssignCommand, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events.{
  TicketAssigned, TicketClosed, TicketOpened,
}
import gleavent_sourced/facts
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit([
    "gleavent_sourced/bulk_assign_handler_v2_test",
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

pub fn successful_bulk_assign_multiple_tickets_test() {
  test_runner.txn(fn(db) {
    // Setup: Create multiple unassigned tickets
    let initial_events = [
      TicketOpened("T-100", "Bug 1", "First bug", "high"),
      TicketOpened("T-101", "Bug 2", "Second bug", "medium"),
      TicketOpened("T-102", "Bug 3", "Third bug", "low"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Create bulk assign command for all three tickets
    let command =
      BulkAssignCommand(
        ["T-100", "T-101", "T-102"],
        "alice@example.com",
        "2024-01-01T10:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful bulk assignment creates events for all tickets
    let assert CommandAccepted(events) = result
    assert list.length(events) == 3
    let assert [
      TicketAssigned("T-100", "alice@example.com", "2024-01-01T10:00:00Z"),
      TicketAssigned("T-101", "alice@example.com", "2024-01-01T10:00:00Z"),
      TicketAssigned("T-102", "alice@example.com", "2024-01-01T10:00:00Z"),
    ] = events
  })
}

pub fn bulk_assign_with_missing_tickets_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create only some of the tickets
    let initial_events = [
      TicketOpened("T-200", "Existing bug 1", "This exists", "high"),
      TicketOpened("T-202", "Existing bug 2", "This also exists", "low"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to bulk assign including non-existent tickets
    let command =
      BulkAssignCommand(
        ["T-200", "T-201", "T-202", "T-203"],
        // T-201 and T-203 don't exist
        "bob@example.com",
        "2024-01-01T11:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection lists all missing tickets
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    // Should contain both missing ticket IDs
    assert message == "Tickets do not exist: T-201, T-203"
      || message == "Tickets do not exist: T-203, T-201"
  })
}

pub fn bulk_assign_with_closed_tickets_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create tickets with some closed
    let initial_events = [
      TicketOpened("T-300", "Open bug 1", "This is open", "high"),
      TicketOpened("T-301", "Closed bug 1", "This will be closed", "medium"),
      TicketOpened("T-302", "Open bug 2", "This is also open", "low"),
      TicketOpened(
        "T-303",
        "Closed bug 2",
        "This will also be closed",
        "critical",
      ),
      TicketClosed("T-301", "Fixed bug 1", "2024-01-01T09:00:00Z"),
      TicketClosed("T-303", "Fixed bug 2", "2024-01-01T09:30:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to bulk assign including closed tickets
    let command =
      BulkAssignCommand(
        ["T-300", "T-301", "T-302", "T-303"],
        // T-301 and T-303 are closed
        "charlie@example.com",
        "2024-01-01T11:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection lists all closed tickets
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    // Should contain both closed ticket IDs
    assert message == "Cannot assign closed tickets: T-301, T-303"
      || message == "Cannot assign closed tickets: T-303, T-301"
  })
}

pub fn bulk_assign_with_empty_assignee_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create valid tickets
    let initial_events = [
      TicketOpened("T-400", "Valid bug", "This ticket is fine", "medium"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to bulk assign with empty assignee
    let command =
      BulkAssignCommand(
        ["T-400"],
        "",
        // Empty assignee
        "2024-01-01T11:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Assignee cannot be empty"
  })
}

pub fn bulk_assign_single_ticket_works_test() {
  test_runner.txn(fn(db) {
    // Setup: Create one ticket for "bulk" assign
    let initial_events = [
      TicketOpened("T-500", "Single bug", "Only one ticket", "high"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Bulk assign with single ticket
    let command =
      BulkAssignCommand(
        ["T-500"],
        // Single ticket in list
        "dave@example.com",
        "2024-01-01T12:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful assignment
    let assert CommandAccepted(events) = result
    let assert [
      TicketAssigned("T-500", "dave@example.com", "2024-01-01T12:00:00Z"),
    ] = events
  })
}

pub fn bulk_assign_empty_ticket_list_succeeds_test() {
  test_runner.txn(fn(db) {
    // No setup needed - empty list

    // Bulk assign with empty ticket list
    let command =
      BulkAssignCommand(
        [],
        // Empty ticket list
        "eve@example.com",
        "2024-01-01T13:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed with no events
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful execution with empty event list
    let assert CommandAccepted(events) = result
    assert events == []
  })
}

pub fn bulk_assign_mixed_problems_reports_first_failure_test() {
  test_runner.txn(fn(db) {
    // Setup: Mix of existing, missing, and closed tickets
    let initial_events = [
      TicketOpened("T-600", "Good ticket", "This exists and is open", "medium"),
      TicketOpened("T-602", "Closed ticket", "This will be closed", "low"),
      TicketClosed("T-602", "Already resolved", "2024-01-01T08:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try bulk assign with mixed problems: missing and closed tickets
    let command =
      BulkAssignCommand(
        ["T-600", "T-601", "T-602"],
        // T-601 missing, T-602 closed
        "frank@example.com",
        "2024-01-01T14:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection - validation order means missing tickets are checked first
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Tickets do not exist: T-601"
  })
}

pub fn bulk_assign_already_assigned_tickets_succeeds_test() {
  test_runner.txn(fn(db) {
    // Setup: Create tickets with some already assigned
    let initial_events = [
      TicketOpened("T-700", "Unassigned bug", "No one working on this", "high"),
      TicketOpened(
        "T-701",
        "Assigned bug",
        "Someone is working on this",
        "medium",
      ),
      TicketAssigned(
        "T-701",
        "old-assignee@example.com",
        "2024-01-01T08:00:00Z",
      ),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Bulk assign including already assigned ticket (should allow reassignment)
    let command =
      BulkAssignCommand(
        ["T-700", "T-701"],
        "new-assignee@example.com",
        "2024-01-01T15:00:00Z",
      )
    let handler = bulk_assign_handler.create_bulk_assign_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed (reassignment allowed)
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful bulk assignment including reassignment
    let assert CommandAccepted(events) = result
    let assert [
      TicketAssigned(
        "T-700",
        "new-assignee@example.com",
        "2024-01-01T15:00:00Z",
      ),
      TicketAssigned(
        "T-701",
        "new-assignee@example.com",
        "2024-01-01T15:00:00Z",
      ),
    ] = events
  })
}
