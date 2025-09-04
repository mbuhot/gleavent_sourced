import gleam/dict
import gleavent_sourced/command_handler_v2.{CommandAccepted, CommandRejected}
import gleavent_sourced/customer_support/mark_duplicate_handler_v2
import gleavent_sourced/customer_support/ticket_commands.{
  BusinessRuleViolation, MarkDuplicateCommand,
}
import gleavent_sourced/customer_support/ticket_events.{
  TicketMarkedDuplicate, TicketOpened,
}
import gleavent_sourced/facts_v2
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit([
    "gleavent_sourced/mark_duplicate_handler_v2_test",
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

pub fn successful_duplicate_marking_test() {
  test_runner.txn(fn(db) {
    // Setup: Create both original and duplicate tickets
    let initial_events = [
      TicketOpened("T-100", "Original bug", "The original issue", "high"),
      TicketOpened("T-101", "Duplicate bug", "Same issue as T-100", "medium"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Create command and handler
    let command =
      MarkDuplicateCommand(
        "T-101",
        // duplicate_ticket_id
        "T-100",
        // original_ticket_id
        "2024-01-01T15:00:00Z",
        // marked_at
      )
    let handler =
      mark_duplicate_handler_v2.create_mark_duplicate_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify successful duplicate marking
    let assert CommandAccepted(events) = result
    let assert [TicketMarkedDuplicate("T-101", "T-100", "2024-01-01T15:00:00Z")] =
      events
  })
}

pub fn mark_duplicate_with_missing_original_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create only the duplicate ticket, original doesn't exist
    let initial_events = [
      TicketOpened("T-102", "Duplicate bug", "This ticket exists", "medium"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to mark T-102 as duplicate of non-existent T-999
    let command =
      MarkDuplicateCommand(
        "T-102",
        // duplicate_ticket_id (exists)
        "T-999",
        // original_ticket_id (doesn't exist)
        "2024-01-01T15:00:00Z",
      )
    let handler =
      mark_duplicate_handler_v2.create_mark_duplicate_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Original ticket does not exist"
  })
}

pub fn mark_duplicate_with_missing_duplicate_ticket_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create only the original ticket, duplicate doesn't exist
    let initial_events = [
      TicketOpened("T-103", "Original bug", "The original issue", "high"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to mark non-existent T-999 as duplicate of T-103
    let command =
      MarkDuplicateCommand(
        "T-999",
        // duplicate_ticket_id (doesn't exist)
        "T-103",
        // original_ticket_id (exists)
        "2024-01-01T15:00:00Z",
      )
    let handler =
      mark_duplicate_handler_v2.create_mark_duplicate_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Duplicate ticket does not exist"
  })
}

pub fn mark_already_duplicate_ticket_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create tickets and already mark one as duplicate
    let initial_events = [
      TicketOpened("T-104", "Original bug", "The original issue", "high"),
      TicketOpened("T-105", "First duplicate", "Same as T-104", "medium"),
      TicketOpened("T-106", "Second duplicate", "Also same as T-104", "low"),
      TicketMarkedDuplicate("T-105", "T-104", "2024-01-01T12:00:00Z"),
      // T-105 already marked as duplicate of T-104
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to mark T-105 as duplicate of T-106 (but T-105 is already marked as duplicate)
    let command =
      MarkDuplicateCommand(
        "T-105",
        // Already marked as duplicate
        "T-106",
        "2024-01-01T15:00:00Z",
      )
    let handler =
      mark_duplicate_handler_v2.create_mark_duplicate_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Ticket is already marked as duplicate"
  })
}

pub fn mark_duplicate_with_both_tickets_missing_fails_test() {
  test_runner.txn(fn(db) {
    // No setup - both tickets don't exist

    // Try to mark non-existent T-998 as duplicate of non-existent T-999
    let command =
      MarkDuplicateCommand(
        "T-998",
        // duplicate_ticket_id (doesn't exist)
        "T-999",
        // original_ticket_id (doesn't exist)
        "2024-01-01T15:00:00Z",
      )
    let handler =
      mark_duplicate_handler_v2.create_mark_duplicate_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection - should fail on original ticket first
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Original ticket does not exist"
  })
}

pub fn mark_self_as_duplicate_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create one ticket to test self-reference rejection
    // This tests that a ticket cannot be marked as duplicate of itself
    let initial_events = [
      TicketOpened(
        "T-107",
        "Self-referencing bug",
        "This will reference itself",
        "medium",
      ),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to mark T-107 as duplicate of itself (should be rejected)
    let command =
      MarkDuplicateCommand(
        "T-107",
        // duplicate_ticket_id
        "T-107",
        // original_ticket_id (same as duplicate)
        "2024-01-01T15:00:00Z",
      )
    let handler =
      mark_duplicate_handler_v2.create_mark_duplicate_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Ticket cannot be marked as duplicate of itself"
  })
}

pub fn mark_duplicate_creates_correct_event_structure_test() {
  test_runner.txn(fn(db) {
    // Setup: Create both tickets with specific details
    let initial_events = [
      TicketOpened(
        "T-200",
        "Bug in authentication",
        "Users can't log in",
        "critical",
      ),
      TicketOpened("T-201", "Login not working", "Same login issue", "high"),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Create command with specific timestamp
    let command = MarkDuplicateCommand("T-201", "T-200", "2024-03-15T14:30:45Z")
    let handler =
      mark_duplicate_handler_v2.create_mark_duplicate_handler_v2(command)
    let metadata = create_test_metadata()

    // Execute command
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify event structure matches exactly
    let assert CommandAccepted(events) = result
    let assert [TicketMarkedDuplicate(duplicate_id, original_id, marked_at)] =
      events
    assert duplicate_id == "T-201"
    assert original_id == "T-200"
    assert marked_at == "2024-03-15T14:30:45Z"
  })
}
