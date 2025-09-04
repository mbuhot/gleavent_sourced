import gleam/dict
import gleavent_sourced/command_handler_v2.{CommandAccepted, CommandRejected}
import gleavent_sourced/customer_support/ticket_command_router
import gleavent_sourced/customer_support/ticket_commands
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/facts
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit_verbose(
    ["gleavent_sourced/mark_duplicate_test"],
    verbose: True,
  )
}

pub fn create_test_metadata() -> dict.Dict(String, String) {
  dict.from_list([
    #("source", "ticket_service"),
    #("version", "1"),
  ])
}

pub fn mark_duplicate_behavior_test() {
  test_runner.txn(fn(db) {
    // Setup: Create two tickets that exist
    let original_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Original ticket",
        description: "This is the original ticket",
        priority: "high",
      )

    let duplicate_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Duplicate ticket",
        description: "This is actually the same issue as T-100",
        priority: "medium",
      )

    let initial_events = [original_opened, duplicate_opened]
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

    // Action: Mark T-200 as duplicate of T-100
    let mark_duplicate_command =
      ticket_command_router.MarkDuplicate(ticket_commands.MarkDuplicateCommand(
        duplicate_ticket_id: "T-200",
        original_ticket_id: "T-100",
        marked_at: "2024-01-01T10:00:00Z",
      ))

    let assert Ok(CommandAccepted(events)) =
      ticket_command_router.handle_ticket_command(mark_duplicate_command, db)

    // Verify: TicketMarkedDuplicate event was created
    let assert [
      ticket_events.TicketMarkedDuplicate(
        "T-200",
        "T-100",
        "2024-01-01T10:00:00Z",
      ),
    ] = events

    // Verify: Check duplicate status facts for both tickets
    // T-100 should show as having a duplicate (DuplicatedBy)
    let original_status_fact =
      ticket_facts.duplicate_status("T-100", fn(ctx, status) {
        dict.insert(ctx, "T-100", status)
      })
    let duplicate_status_fact =
      ticket_facts.duplicate_status("T-200", fn(ctx, status) {
        dict.insert(ctx, "T-200", status)
      })

    let assert Ok(results) =
      facts.query_event_log(
        db,
        [original_status_fact, duplicate_status_fact],
        dict.new(),
        ticket_events.decode,
      )

    // Assertions: Verify the business behavior
    let assert Ok(ticket_facts.DuplicatedBy("T-200")) =
      dict.get(results, "T-100")
    let assert Ok(ticket_facts.DuplicateOf("T-100")) =
      dict.get(results, "T-200")
  })
}

pub fn mark_duplicate_validation_rules_test() {
  test_runner.txn(fn(db) {
    // Setup: Create only one ticket
    let original_opened =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Original ticket",
        description: "This is the original ticket",
        priority: "high",
      )

    let test_metadata = create_test_metadata()

    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        [original_opened],
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Action: Try to mark non-existent ticket as duplicate
    let invalid_command =
      ticket_command_router.MarkDuplicate(ticket_commands.MarkDuplicateCommand(
        duplicate_ticket_id: "T-999",
        // Does not exist
        original_ticket_id: "T-100",
        marked_at: "2024-01-01T10:00:00Z",
      ))

    // Verify: Command should be rejected
    let assert Ok(CommandRejected(ticket_commands.BusinessRuleViolation(message))) =
      ticket_command_router.handle_ticket_command(invalid_command, db)

    assert message == "Duplicate ticket does not exist"
  })
}
