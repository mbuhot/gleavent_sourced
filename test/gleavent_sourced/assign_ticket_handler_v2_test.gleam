import gleam/dict
import gleavent_sourced/command_handler_v2.{CommandAccepted, CommandRejected}
import gleavent_sourced/customer_support/assign_ticket_handler_v2
import gleavent_sourced/customer_support/ticket_commands.{
  AssignTicketCommand, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events.{
  TicketAssigned, TicketClosed, TicketOpened,
}
import gleavent_sourced/facts_v2
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit([
    "gleavent_sourced/assign_ticket_handler_v2_test",
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
    facts_v2.append_events(db, events, ticket_events.encode, test_metadata, [], 0)
}

pub fn successful_assignment_creates_event_test() {
  test_runner.txn(fn(db) {
    // Setup: Create an unassigned ticket
    let initial_events = [
      TicketOpened("T-100", "Bug report", "System crashes", "medium"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Create command and handler
    let command = AssignTicketCommand("T-100", "alice@example.com", "2024-01-01T10:00:00Z")
    let handler = assign_ticket_handler_v2.create_assign_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command
    let assert Ok(result) = command_handler_v2.execute(db, handler, command, metadata)

    // Verify successful assignment
    let assert CommandAccepted(events) = result
    let assert [TicketAssigned("T-100", "alice@example.com", "2024-01-01T10:00:00Z")] = events
  })
}

pub fn assignment_to_already_assigned_ticket_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create a ticket that's already assigned
    let initial_events = [
      TicketOpened("T-101", "UI Bug", "Button not working", "low"),
      TicketAssigned("T-101", "bob@example.com", "2024-01-01T09:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to assign to different person
    let command = AssignTicketCommand("T-101", "alice@example.com", "2024-01-01T10:00:00Z")
    let handler = assign_ticket_handler_v2.create_assign_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) = command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Ticket already assigned to bob@example.com"
  })
}

pub fn assignment_to_nonexistent_ticket_fails_test() {
  test_runner.txn(fn(db) {
    // No setup - ticket doesn't exist

    // Try to assign to non-existent ticket
    let command = AssignTicketCommand("T-999", "alice@example.com", "2024-01-01T10:00:00Z")
    let handler = assign_ticket_handler_v2.create_assign_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) = command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Ticket does not exist"
  })
}

pub fn assignment_to_closed_ticket_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create a closed ticket
    let initial_events = [
      TicketOpened("T-102", "Performance issue", "App is slow", "high"),
      TicketAssigned("T-102", "bob@example.com", "2024-01-01T09:00:00Z"),
      TicketClosed("T-102", "Fixed performance bottleneck", "2024-01-01T11:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to assign closed ticket to different person
    let command = AssignTicketCommand("T-102", "alice@example.com", "2024-01-01T12:00:00Z")
    let handler = assign_ticket_handler_v2.create_assign_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) = command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Cannot assign closed ticket"
  })
}

pub fn empty_assignee_validation_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create an unassigned ticket
    let initial_events = [
      TicketOpened("T-103", "Data issue", "Incorrect calculation", "medium"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to assign with empty assignee
    let command = AssignTicketCommand("T-103", "", "2024-01-01T10:00:00Z")
    let handler = assign_ticket_handler_v2.create_assign_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) = command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Assignee cannot be empty"
  })
}

pub fn empty_assigned_at_validation_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create an unassigned ticket
    let initial_events = [
      TicketOpened("T-104", "Security issue", "Potential vulnerability", "critical"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to assign with empty assigned_at timestamp
    let command = AssignTicketCommand("T-104", "alice@example.com", "")
    let handler = assign_ticket_handler_v2.create_assign_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) = command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Assigned at cannot be empty"
  })
}
