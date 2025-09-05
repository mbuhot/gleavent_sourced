import gleam/dict
import gleavent_sourced/command_handler_v2.{CommandAccepted, CommandRejected}
import gleavent_sourced/customer_support/close_ticket_handler_v2
import gleavent_sourced/customer_support/ticket_commands.{
  BusinessRuleViolation, CloseTicketCommand,
}
import gleavent_sourced/customer_support/ticket_events.{
  TicketAssigned, TicketClosed, TicketOpened, TicketParentLinked,
}
import gleavent_sourced/facts_v2
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit([
    "gleavent_sourced/close_ticket_handler_test",
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
    facts_v2.append_events(
      db,
      events,
      ticket_events.encode,
      test_metadata,
      [],
      0,
    )
}

pub fn successful_close_with_valid_resolution_test() {
  test_runner.txn(fn(db) {
    // Setup: Create, assign, then close a high priority ticket with detailed resolution
    let initial_events = [
      TicketOpened("T-200", "Critical bug", "System crashes", "high"),
      TicketAssigned("T-200", "alice@example.com", "2024-01-01T10:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Create command and handler
    let command =
      CloseTicketCommand(
        "T-200",
        "Fixed by implementing proper error handling and adding validation checks",
        "2024-01-01T15:00:00Z",
        "alice@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify successful close
    let assert CommandAccepted(events) = result
    let assert [TicketClosed("T-200", resolution, "2024-01-01T15:00:00Z")] =
      events
    assert resolution
      == "Fixed by implementing proper error handling and adding validation checks"
  })
}

pub fn close_nonexistent_ticket_fails_test() {
  test_runner.txn(fn(db) {
    // No setup - ticket doesn't exist

    // Try to close non-existent ticket
    let command =
      CloseTicketCommand(
        "T-999",
        "Fixed",
        "2024-01-01T16:00:00Z",
        "alice@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Ticket does not exist"
  })
}

pub fn close_with_insufficient_resolution_for_high_priority_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create and assign a high priority ticket
    let initial_events = [
      TicketOpened("T-201", "Another high priority bug", "System crash", "high"),
      TicketAssigned("T-201", "bob@example.com", "2024-01-01T11:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to close with insufficient resolution (< 20 characters)
    let command =
      CloseTicketCommand(
        "T-201",
        "Fixed",
        // Only 5 characters
        "2024-01-01T16:00:00Z",
        "bob@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message
      == "High priority tickets require detailed resolution (minimum 20 characters)"
  })
}

pub fn close_by_wrong_person_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create and assign ticket to specific person
    let initial_events = [
      TicketOpened("T-202", "Bug report", "Something is broken", "medium"),
      TicketAssigned("T-202", "bob@example.com", "2024-01-01T11:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to close by different person
    let command =
      CloseTicketCommand(
        "T-202",
        "Fixed the issue completely",
        "2024-01-01T16:00:00Z",
        "charlie@example.com",
        // Not the assignee
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message
      == "Only the assignee (bob@example.com) can close this ticket"
  })
}

pub fn close_already_closed_ticket_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create, assign, and already close a ticket
    let initial_events = [
      TicketOpened("T-203", "Fixed bug", "Was already resolved", "low"),
      TicketAssigned("T-203", "alice@example.com", "2024-01-01T10:00:00Z"),
      TicketClosed("T-203", "Already resolved", "2024-01-01T14:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to close already closed ticket
    let command =
      CloseTicketCommand(
        "T-203",
        "Trying to close again",
        "2024-01-01T16:00:00Z",
        "alice@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Ticket is already closed"
  })
}

pub fn close_unassigned_ticket_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create ticket but don't assign it
    let initial_events = [
      TicketOpened(
        "T-204",
        "Unassigned bug",
        "Nobody is working on this",
        "medium",
      ),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to close unassigned ticket
    let command =
      CloseTicketCommand(
        "T-204",
        "Trying to close unassigned ticket",
        "2024-01-01T16:00:00Z",
        "alice@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Ticket must be assigned before it can be closed"
  })
}

pub fn close_parent_with_open_children_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create parent ticket, child ticket, link them, assign parent
    // Keep child ticket open
    let initial_events = [
      TicketOpened("T-205", "Parent ticket", "Main issue", "high"),
      TicketOpened("T-206", "Child ticket", "Sub-issue", "medium"),
      TicketParentLinked("T-206", "T-205"),
      // T-206 is child of T-205
      TicketAssigned("T-205", "alice@example.com", "2024-01-01T10:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to close parent while child is still open
    let command =
      CloseTicketCommand(
        "T-205",
        "Fixed the main issue but child is still open",
        "2024-01-01T16:00:00Z",
        "alice@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Cannot close parent ticket with open child tickets"
  })
}

pub fn close_parent_with_closed_children_succeeds_test() {
  test_runner.txn(fn(db) {
    // Setup: Create parent ticket, child ticket, link them, assign both, close child
    let initial_events = [
      TicketOpened("T-207", "Parent ticket", "Main issue", "medium"),
      TicketOpened("T-208", "Child ticket", "Sub-issue", "low"),
      TicketParentLinked("T-208", "T-207"),
      // T-208 is child of T-207
      TicketAssigned("T-207", "alice@example.com", "2024-01-01T10:00:00Z"),
      TicketAssigned("T-208", "bob@example.com", "2024-01-01T11:00:00Z"),
      TicketClosed("T-208", "Child issue resolved", "2024-01-01T14:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to close parent - should succeed since child is closed
    let command =
      CloseTicketCommand(
        "T-207",
        "Main issue resolved, all children closed",
        "2024-01-01T16:00:00Z",
        "alice@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify successful close
    let assert CommandAccepted(events) = result
    let assert [TicketClosed("T-207", resolution, "2024-01-01T16:00:00Z")] =
      events
    assert resolution == "Main issue resolved, all children closed"
  })
}

pub fn empty_resolution_validation_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create and assign a low priority ticket
    let initial_events = [
      TicketOpened("T-209", "Low priority bug", "Minor issue", "low"),
      TicketAssigned("T-209", "alice@example.com", "2024-01-01T10:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to close with empty resolution
    let command =
      CloseTicketCommand(
        "T-209",
        "",
        // Empty resolution
        "2024-01-01T16:00:00Z",
        "alice@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Resolution cannot be empty"
  })
}

pub fn empty_closed_at_validation_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create and assign a ticket
    let initial_events = [
      TicketOpened("T-210", "Some bug", "Issue description", "medium"),
      TicketAssigned("T-210", "alice@example.com", "2024-01-01T10:00:00Z"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to close with empty closed_at timestamp
    let command =
      CloseTicketCommand(
        "T-210",
        "Fixed the issue",
        "",
        // Empty closed_at
        "alice@example.com",
      )
    let handler =
      close_ticket_handler_v2.create_close_ticket_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Closed at cannot be empty"
  })
}
