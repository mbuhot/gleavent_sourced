import gleam/dict
import gleam/list
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/ticket_events_test"])
}

pub fn create_test_metadata() -> dict.Dict(String, String) {
  dict.from_list([
    #("source", "ticket_service"),
    #("version", "1"),
  ])
}

pub fn complete_ticket_lifecycle_test() {
  test_runner.txn(fn(db) {
    // Test complete ticket lifecycle: open -> assign -> close
    let opened_event =
      ticket_events.TicketOpened(
        ticket_id: "T-001",
        title: "Fix login bug",
        description: "Users cannot log in with special characters",
        priority: "high",
      )

    let assigned_event =
      ticket_events.TicketAssigned(
        ticket_id: "T-001",
        assignee: "john.doe@example.com",
        assigned_at: "2024-01-15T10:30:00Z",
      )

    let closed_event =
      ticket_events.TicketClosed(
        ticket_id: "T-001",
        resolution: "Fixed character encoding in login form",
        closed_at: "2024-01-16T14:45:00Z",
      )

    let ticket_events = [opened_event, assigned_event, closed_event]

    let test_metadata = create_test_metadata()

    // Store ticket events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        ticket_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Query events back using the high-level API
    let ticket_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-001"),
      ])
      |> event_filter.for_type("TicketAssigned", [
        event_filter.attr_string("ticket_id", "T-001"),
      ])
      |> event_filter.for_type("TicketClosed", [
        event_filter.attr_string("ticket_id", "T-001"),
      ])
      |> event_filter.with_tag("lifecycle_test")

    let assert Ok(#(events, _max_seq)) =
      event_log.query_events(db, ticket_filter, ticket_events.decode)

    // Verify complete lifecycle: all 3 events stored and retrieved correctly
    let assert 3 = list.length(events)

    // Verify we have the correct event types by checking the actual events
    assert list.contains(events, opened_event)
    assert list.contains(events, assigned_event)
    assert list.contains(events, closed_event)
  })
}

pub fn event_filtering_by_attributes_test() {
  test_runner.txn(fn(db) {
    // Create tickets with different attributes to test filtering
    let high_priority_ticket =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Critical system down",
        description: "Production system is offline",
        priority: "high",
      )

    let medium_priority_ticket =
      ticket_events.TicketOpened(
        ticket_id: "T-101",
        title: "Minor UI issue",
        description: "Button alignment is off",
        priority: "medium",
      )

    let assignment =
      ticket_events.TicketAssigned(
        ticket_id: "T-100",
        assignee: "senior.dev@example.com",
        assigned_at: "2024-01-01T09:00:00Z",
      )

    let test_metadata = create_test_metadata()
    let all_events = [high_priority_ticket, medium_priority_ticket, assignment]

    // Store events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        all_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Test filtering: find high priority tickets
    // Test filtering by attributes
    let high_priority_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("priority", "high"),
      ])
      |> event_filter.with_tag("high_priority_test")

    let assert Ok(#(events, _max_seq)) =
      event_log.query_events(db, high_priority_filter, ticket_events.decode)

    // Should find only the high priority ticket
    let assert 1 = list.length(events)
    let assert [
      ticket_events.TicketOpened(ticket_id: "T-100", priority: "high", ..),
    ] = events

    // Test multi-condition filtering: high priority OR T-100 assignments
    let complex_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("priority", "high"),
      ])
      |> event_filter.for_type("TicketAssigned", [
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.with_tag("complex_test")

    let assert Ok(#(complex_events, _)) =
      event_log.query_events(db, complex_filter, ticket_events.decode)

    // Should find both the high priority ticket and the assignment
    let assert 2 = list.length(complex_events)

    // Test multiple attributes for same event type: high priority AND T-100 tickets
    let multi_attr_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("priority", "high"),
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.with_tag("multi_attr_test")

    let assert Ok(#(multi_attr_events, _)) =
      event_log.query_events(db, multi_attr_filter, ticket_events.decode)

    // Should find only the T-100 high priority ticket (both conditions must match)
    let assert 1 = list.length(multi_attr_events)
    let assert [
      ticket_events.TicketOpened(ticket_id: "T-100", priority: "high", ..),
    ] = multi_attr_events
  })
}

pub fn multiple_attribute_filters_behavior_test() {
  test_runner.txn(fn(db) {
    // Create tickets to test AND vs OR behavior with multiple attributes
    let ticket_high_t100 =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "High priority T-100",
        description: "Matches both priority=high AND ticket_id=T-100",
        priority: "high",
      )

    let ticket_high_t200 =
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "High priority T-200",
        description: "Matches priority=high but NOT ticket_id=T-100",
        priority: "high",
      )

    let ticket_low_t100 =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Low priority T-100",
        description: "Matches ticket_id=T-100 but NOT priority=high",
        priority: "low",
      )

    let test_metadata = create_test_metadata()
    let all_events = [ticket_high_t100, ticket_high_t200, ticket_low_t100]

    // Store events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        all_events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Test multiple AttributeFilters: priority=high AND ticket_id=T-100
    let multi_attr_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("priority", "high"),
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.with_tag("multi_attr_behavior_test")

    let assert Ok(#(filtered_events, _)) =
      event_log.query_events(db, multi_attr_filter, ticket_events.decode)

    // Current implementation: Should return 3 events (OR behavior)
    // Expected for AND: Should return 1 event (only ticket_high_t100)
    // Let's see what we actually get
    let event_count = list.length(filtered_events)

    // With AND behavior: should get 1 event (only high_t100 matches both conditions)
    let assert 1 = event_count
  })
}

pub fn optimistic_concurrency_control_prevents_conflicts_test() {
  test_runner.txn(fn(db) {
    // Simulate concurrent modification scenario

    // Step 1: Process A reads current state
    let opened_event =
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Concurrency test ticket",
        description: "Testing optimistic locking",
        priority: "medium",
      )

    let test_metadata = create_test_metadata()

    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        [opened_event],
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Process A reads current state and gets sequence number from events
    // Query to get current state before Process B appends
    let initial_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-200"),
      ])
      |> event_filter.with_tag("initial_state")

    let assert Ok(#(initial_events, process_a_last_seen)) =
      event_log.query_events(db, initial_filter, ticket_events.decode)

    let assert 1 = list.length(initial_events)

    // Step 2: Process B modifies the ticket (simulating concurrent access)
    let assignment_event_b =
      ticket_events.TicketAssigned(
        ticket_id: "T-200",
        assignee: "process.b@example.com",
        assigned_at: "2024-01-01T10:00:00Z",
      )

    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        [assignment_event_b],
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
        // Process B bypasses conflict check
      )

    // Step 3: Process A tries to modify using stale sequence number
    let process_a_event =
      ticket_events.TicketClosed(
        ticket_id: "T-200",
        resolution: "Process A resolution",
        closed_at: "2024-01-01T11:00:00Z",
      )

    // Process A uses conflict filter to detect T-200 assignments
    let conflict_filter =
      event_filter.new()
      |> event_filter.for_type("TicketAssigned", [
        event_filter.attr_string("ticket_id", "T-200"),
      ])

    let result =
      event_log.append_events(
        db,
        [process_a_event],
        ticket_events.encode,
        test_metadata,
        conflict_filter,
        process_a_last_seen,
        // Stale sequence number
      )

    // Should detect conflict and reject Process A's modification
    let assert Ok(event_log.AppendConflict(conflict_count: 1)) = result

    // Verify Process A's event was NOT applied using high-level query
    // Query final events to verify both processes' events were stored
    let final_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-200"),
      ])
      |> event_filter.for_type("TicketAssigned", [
        event_filter.attr_string("ticket_id", "T-200"),
      ])
      |> event_filter.for_type("TicketClosed", [
        event_filter.attr_string("ticket_id", "T-200"),
      ])
      |> event_filter.with_tag("final_state")

    let assert Ok(#(final_events, _)) =
      event_log.query_events(db, final_filter, ticket_events.decode)

    // Should have only 2 events: initial + Process B's assignment
    assert list.length(final_events) == 2
    assert list.contains(final_events, opened_event)
    assert list.contains(final_events, assignment_event_b)

    // Define a closed event that should NOT be in the results
    let closed_event =
      ticket_events.TicketClosed(
        ticket_id: "T-200",
        resolution: "Not actually closed",
        closed_at: "2024-01-01T12:00:00Z",
      )
    assert !list.contains(final_events, closed_event)
  })
}
