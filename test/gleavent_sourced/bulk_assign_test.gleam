import gleam/dict
import gleam/list
import gleavent_sourced/command_handler.{CommandAccepted, CommandRejected}
import gleavent_sourced/customer_support/ticket_command_router
import gleavent_sourced/customer_support/ticket_commands
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit_verbose(
    ["gleavent_sourced/bulk_assign_test"],
    verbose: True,
  )
}

pub fn create_test_metadata() -> dict.Dict(String, String) {
  dict.from_list([
    #("source", "ticket_service"),
    #("version", "1"),
  ])
}

pub fn bulk_assign_multiple_tickets_test() {
  test_runner.txn(fn(db) {
    // Setup: Create three tickets
    let ticket1_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "First ticket",
        description: "This is the first ticket",
        priority: "high",
      )

    let ticket2_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Second ticket",
        description: "This is the second ticket",
        priority: "medium",
      )

    let ticket3_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-300",
        title: "Third ticket",
        description: "This is the third ticket",
        priority: "low",
      )

    let initial_events = [ticket1_opened, ticket2_opened, ticket3_opened]
    let test_metadata = create_test_metadata()

    // Store initial ticket events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        initial_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Action: Bulk assign all three tickets
    let bulk_assign_command =
      ticket_command_router.BulkAssign(ticket_commands.BulkAssignCommand(
        ticket_ids: ["T-100", "T-200", "T-300"],
        assignee: "alice@example.com",
        assigned_at: "2024-01-01T10:00:00Z",
      ))

    let assert Ok(CommandAccepted(events)) =
      ticket_command_router.handle_ticket_command(bulk_assign_command, db)

    // Verify: Three TicketAssigned events were created
    assert list.length(events) == 3

    // Verify: Each event has correct structure and content
    let assert [
      ticket_events.TicketAssigned(
        "T-100",
        "alice@example.com",
        "2024-01-01T10:00:00Z",
      ),
      ticket_events.TicketAssigned(
        "T-200",
        "alice@example.com",
        "2024-01-01T10:00:00Z",
      ),
      ticket_events.TicketAssigned(
        "T-300",
        "alice@example.com",
        "2024-01-01T10:00:00Z",
      ),
    ] = events
  })
}

pub fn bulk_assign_with_nonexistent_ticket_rejected_test() {
  test_runner.txn(fn(db) {
    // Setup: Create only two tickets
    let ticket1_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "First ticket",
        description: "This is the first ticket",
        priority: "high",
      )

    let ticket2_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Second ticket",
        description: "This is the second ticket",
        priority: "medium",
      )

    let initial_events = [ticket1_opened, ticket2_opened]
    let test_metadata = create_test_metadata()

    // Store initial ticket events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        initial_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Action: Try to bulk assign including non-existent ticket T-300
    let bulk_assign_command =
      ticket_command_router.BulkAssign(ticket_commands.BulkAssignCommand(
        ticket_ids: ["T-100", "T-200", "T-300"],
        assignee: "alice@example.com",
        assigned_at: "2024-01-01T10:00:00Z",
      ))

    // Verify: Command should be rejected due to non-existent ticket
    let assert Ok(CommandRejected(ticket_commands.BusinessRuleViolation(message))) =
      ticket_command_router.handle_ticket_command(bulk_assign_command, db)

    assert message == "Tickets do not exist: T-300"
  })
}

pub fn bulk_assign_with_closed_tickets_rejected_test() {
  test_runner.txn(fn(db) {
    // Setup: Create three tickets
    let ticket1_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "First ticket",
        description: "This is the first ticket",
        priority: "high",
      )

    let ticket2_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Second ticket",
        description: "This is the second ticket",
        priority: "medium",
      )

    let ticket3_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-300",
        title: "Third ticket",
        description: "This is the third ticket",
        priority: "low",
      )

    // Close ticket T-200
    let ticket2_closed =
      ticket_events.TicketClosed(
        ticket_id: "T-200",
        resolution: "Already resolved",
        closed_at: "2024-01-01T09:00:00Z",
      )

    let initial_events = [ticket1_opened, ticket2_opened, ticket3_opened, ticket2_closed]
    let test_metadata = create_test_metadata()

    // Store initial ticket events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        initial_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Action: Try to bulk assign including closed ticket T-200
    let bulk_assign_command =
      ticket_command_router.BulkAssign(ticket_commands.BulkAssignCommand(
        ticket_ids: ["T-100", "T-200", "T-300"],
        assignee: "alice@example.com",
        assigned_at: "2024-01-01T10:00:00Z",
      ))

    // Verify: Command should be rejected due to closed ticket
    let assert Ok(CommandRejected(ticket_commands.BusinessRuleViolation(message))) =
      ticket_command_router.handle_ticket_command(bulk_assign_command, db)

    assert message == "Cannot assign closed tickets: T-200"
  })
}

pub fn bulk_assign_with_empty_assignee_rejected_test() {
  test_runner.txn(fn(db) {
    // Setup: Create a ticket
    let ticket_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Test ticket",
        description: "This is a test ticket",
        priority: "medium",
      )

    let initial_events = [ticket_opened]
    let test_metadata = create_test_metadata()

    // Store initial ticket events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        initial_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Action: Try to bulk assign with empty assignee
    let bulk_assign_command =
      ticket_command_router.BulkAssign(ticket_commands.BulkAssignCommand(
        ticket_ids: ["T-100"],
        assignee: "",
        assigned_at: "2024-01-01T10:00:00Z",
      ))

    // Verify: Command should be rejected due to empty assignee
    let assert Ok(CommandRejected(ticket_commands.BusinessRuleViolation(message))) =
      ticket_command_router.handle_ticket_command(bulk_assign_command, db)

    assert message == "Assignee cannot be empty"
  })
}

pub fn bulk_assign_with_multiple_validation_failures_test() {
  test_runner.txn(fn(db) {
    // Setup: Create two tickets, close one
    let ticket1_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "First ticket",
        description: "This is the first ticket",
        priority: "high",
      )

    let ticket2_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Second ticket",
        description: "This is the second ticket",
        priority: "medium",
      )

    // Close ticket T-200
    let ticket2_closed =
      ticket_events.TicketClosed(
        ticket_id: "T-200",
        resolution: "Already resolved",
        closed_at: "2024-01-01T09:00:00Z",
      )

    let initial_events = [ticket1_opened, ticket2_opened, ticket2_closed]
    let test_metadata = create_test_metadata()

    // Store initial ticket events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        initial_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Action: Try to bulk assign including closed T-200 and nonexistent T-300
    let bulk_assign_command =
      ticket_command_router.BulkAssign(ticket_commands.BulkAssignCommand(
        ticket_ids: ["T-100", "T-200", "T-300"],
        assignee: "alice@example.com",
        assigned_at: "2024-01-01T10:00:00Z",
      ))

    // Verify: Command should be rejected - nonexistent tickets checked first
    let assert Ok(CommandRejected(ticket_commands.BusinessRuleViolation(message))) =
      ticket_command_router.handle_ticket_command(bulk_assign_command, db)

    assert message == "Tickets do not exist: T-300"
  })
}
