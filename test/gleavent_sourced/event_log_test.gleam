import gleam/dict
import gleam/list

import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/event_log_optimized_test"])
}

pub fn create_test_metadata() -> dict.Dict(String, String) {
  dict.from_list([
    #("source", "event_log_test"),
    #("version", "1"),
  ])
}

pub fn query_events_with_tags_basic_functionality_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    // Create test events
    let events = [
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Test ticket",
        description: "Description",
        priority: "high",
      ),
      ticket_events.TicketAssigned(
        ticket_id: "T-100",
        assignee: "john.doe",
        assigned_at: "2024-01-01T10:00:00Z",
      ),
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Another ticket",
        description: "Different ticket",
        priority: "low",
      ),
    ]

    // Store events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Create filter
    let filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.with_tag("ticket_exists")

    // Query using optimized function
    let assert Ok(#(events_by_fact, max_seq)) =
      event_log.query_events_with_tags(db, filter, ticket_events.decode)

    // Verify results
    assert max_seq > 0
    assert dict.size(events_by_fact) == 1

    let assert Ok(found_events) = dict.get(events_by_fact, "ticket_exists")
    assert list.length(found_events) == 1

    let assert [ticket_events.TicketOpened(ticket_id, title, ..)] = found_events
    assert ticket_id == "T-100"
    assert title == "Test ticket"
  })
}

pub fn query_events_with_tags_vs_v1_equivalence_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    // Create test events
    let events = [
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Test ticket",
        description: "Description",
        priority: "high",
      ),
      ticket_events.TicketAssigned(
        ticket_id: "T-100",
        assignee: "john.doe",
        assigned_at: "2024-01-01T10:00:00Z",
      ),
    ]

    // Store events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Create filter
    let filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.with_tag("ticket_exists")

    // Query with optimized function
    let assert Ok(#(events_by_fact, max_seq)) =
      event_log.query_events_with_tags(db, filter, ticket_events.decode)

    // Verify results
    assert max_seq > 0
    assert dict.size(events_by_fact) == 1

    let assert Ok(events) = dict.get(events_by_fact, "ticket_exists")
    assert list.length(events) == 1
  })
}

pub fn query_events_with_tags_multiple_filter_types_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    // Create test events with different data types
    let events = [
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "High priority ticket",
        description: "Urgent issue",
        priority: "high",
      ),
      ticket_events.TicketOpened(
        ticket_id: "T-200",
        title: "Low priority ticket",
        description: "Minor issue",
        priority: "low",
      ),
      ticket_events.TicketAssigned(
        ticket_id: "T-100",
        assignee: "alice.smith",
        assigned_at: "2024-01-01T10:00:00Z",
      ),
    ]

    // Store events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Test string equals filter
    let string_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("priority", "high"),
      ])
      |> event_filter.with_tag("high_priority")

    let assert Ok(#(events_by_fact, _)) =
      event_log.query_events_with_tags(db, string_filter, ticket_events.decode)

    let assert Ok(high_priority_events) =
      dict.get(events_by_fact, "high_priority")
    assert list.length(high_priority_events) == 1

    // Test multiple containment filters (should merge)
    let multi_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-100"),
        event_filter.attr_string("priority", "high"),
      ])
      |> event_filter.with_tag("specific_ticket")

    let assert Ok(#(multi_events_by_fact, _)) =
      event_log.query_events_with_tags(db, multi_filter, ticket_events.decode)

    let assert Ok(specific_events) =
      dict.get(multi_events_by_fact, "specific_ticket")
    assert list.length(specific_events) == 1

    let assert [ticket_events.TicketOpened(ticket_id, _, _, priority)] =
      specific_events
    assert ticket_id == "T-100"
    assert priority == "high"
  })
}

pub fn query_events_with_tags_multiple_event_types_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    // Create events of different types
    let events = [
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Test ticket",
        description: "Description",
        priority: "high",
      ),
      ticket_events.TicketAssigned(
        ticket_id: "T-200",
        assignee: "john.doe",
        assigned_at: "2024-01-01T10:00:00Z",
      ),
      ticket_events.TicketClosed(
        ticket_id: "T-300",
        resolution: "Fixed",
        closed_at: "2024-01-01T12:00:00Z",
      ),
    ]

    // Store events
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Create filter for multiple event types (OR logic)
    let multi_type_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.for_type("TicketAssigned", [
        event_filter.attr_string("assignee", "john.doe"),
      ])
      |> event_filter.with_tag("multi_type")

    let assert Ok(#(events_by_fact, _)) =
      event_log.query_events_with_tags(
        db,
        multi_type_filter,
        ticket_events.decode,
      )

    let assert Ok(found_events) = dict.get(events_by_fact, "multi_type")
    assert list.length(found_events) == 2

    // Should have both TicketOpened and TicketAssigned events
    // Find the TicketOpened event
    let opened_event =
      list.find(found_events, fn(event) {
        case event {
          ticket_events.TicketOpened(..) -> True
          _ -> False
        }
      })
    let assert Ok(ticket_events.TicketOpened(ticket_id: "T-100", ..)) =
      opened_event

    // Find the TicketAssigned event
    let assigned_event =
      list.find(found_events, fn(event) {
        case event {
          ticket_events.TicketAssigned(..) -> True
          _ -> False
        }
      })
    let assert Ok(ticket_events.TicketAssigned(assignee: "john.doe", ..)) =
      assigned_event
  })
}

pub fn append_events_basic_functionality_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    let events = [
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Test ticket",
        description: "Description",
        priority: "high",
      ),
    ]

    let conflict_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.with_tag("conflict_check")

    // First append should succeed
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        conflict_filter,
        0,
      )

    // Verify the event was stored
    let query_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.with_tag("query")

    let assert Ok(#(events_by_fact, _)) =
      event_log.query_events_with_tags(db, query_filter, ticket_events.decode)

    let assert Ok(stored_events) = dict.get(events_by_fact, "query")
    assert list.length(stored_events) == 1
  })
}

pub fn append_events_conflict_detection_test() {
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    let initial_event =
      ticket_events.TicketOpened(
        ticket_id: "T-100",
        title: "Test ticket",
        description: "Description",
        priority: "high",
      )

    // Store initial event
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        [initial_event],
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Get the current max sequence
    let query_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [])
      |> event_filter.with_tag("all_tickets")

    let assert Ok(#(_, max_seq)) =
      event_log.query_events_with_tags(db, query_filter, ticket_events.decode)

    // Try to append with old sequence number (should detect conflict)
    let conflict_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "T-100"),
      ])
      |> event_filter.with_tag("conflict_check")

    let new_event =
      ticket_events.TicketAssigned(
        ticket_id: "T-100",
        assignee: "alice.smith",
        assigned_at: "2024-01-01T10:00:00Z",
      )

    // Should detect conflict since there's already a T-100 ticket after sequence 0
    let assert Ok(event_log.AppendConflict(conflict_count: count)) =
      event_log.append_events(
        db,
        [new_event],
        ticket_events.encode,
        test_metadata,
        conflict_filter,
        0,
        // Old sequence number
      )

    assert count > 0

    // Should succeed with current sequence number
    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        [new_event],
        ticket_events.encode,
        test_metadata,
        conflict_filter,
        max_seq,
        // Current sequence number
      )
  })
}
