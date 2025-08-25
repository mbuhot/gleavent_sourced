import gleam/json
import gleam/list
import gleavent_sourced/customer_support/ticket_event
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/events
import gleavent_sourced/parrot_pog
import gleavent_sourced/sql
import gleavent_sourced/test_runner

import pog

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/ticket_events_test"])
}

pub fn store_different_ticket_event_types_test() {
  test_runner.txn(fn(db) {
    // Create test ticket events
    let opened_event =
      ticket_event.TicketOpened(
        ticket_id: "T-001",
        title: "Fix login bug",
        description: "Users cannot log in with special characters",
        priority: "high",
      )

    let assigned_event =
      ticket_event.TicketAssigned(
        ticket_id: "T-001",
        assignee: "john.doe@example.com",
        assigned_at: "2024-01-15T10:30:00Z",
      )

    let closed_event =
      ticket_event.TicketClosed(
        ticket_id: "T-001",
        resolution: "Fixed character encoding in login form",
        closed_at: "2024-01-16T14:45:00Z",
      )

    let test_metadata = ticket_event.create_test_metadata()

    // Store each event type
    let events = [opened_event, assigned_event, closed_event]

    let assert Ok(_) =
      event_log.append_events(
        db,
        events,
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
      )

    // Read ticket events back using generated function
    let ticket_event_types = ["TicketOpened", "TicketAssigned", "TicketClosed"]
    let #(select_sql, select_params, _decoder) =
      sql.read_events_by_types(event_types: ticket_event_types)

    // Create pog query for select
    let select_query =
      pog.query(select_sql)
      |> parrot_pog.parameters(select_params)
      |> pog.returning(sql.read_events_by_types_decoder())

    // Execute the select
    let assert Ok(returned) = pog.execute(select_query, on: db)
    let raw_rows = returned.rows

    // Decode payloads
    let assert Ok(rows) =
      events.decode_payloads(raw_rows, ticket_event.ticket_events_decoder())

    // Verify we got exactly 3 events back
    assert list.length(rows) == 3

    // Verify first event (TicketOpened)
    let assert [first_event, second_event, third_event] = rows
    assert "TicketOpened" == first_event.event_type
    assert opened_event == first_event.payload

    // Verify second event (TicketAssigned)
    assert "TicketAssigned" == second_event.event_type
    assert assigned_event == second_event.payload

    // Verify third event (TicketClosed)
    assert "TicketClosed" == third_event.event_type
    assert closed_event == third_event.payload
  })
}

pub fn query_events_by_ticket_id_test() {
  test_runner.txn(fn(db) {
    // Create events for multiple tickets
    let ticket1_opened =
      ticket_event.TicketOpened(
        ticket_id: "T-001",
        title: "Fix login bug",
        description: "Users cannot log in",
        priority: "high",
      )

    let ticket1_assigned =
      ticket_event.TicketAssigned(
        ticket_id: "T-001",
        assignee: "alice@example.com",
        assigned_at: "2024-01-15T10:30:00Z",
      )

    let ticket2_opened =
      ticket_event.TicketOpened(
        ticket_id: "T-002",
        title: "Update documentation",
        description: "API docs are outdated",
        priority: "medium",
      )

    let ticket1_closed =
      ticket_event.TicketClosed(
        ticket_id: "T-001",
        resolution: "Fixed character encoding",
        closed_at: "2024-01-16T14:45:00Z",
      )

    let test_metadata = ticket_event.create_test_metadata()

    // Store all events
    let all_events = [
      ticket1_opened,
      ticket1_assigned,
      ticket2_opened,
      ticket1_closed,
    ]

    let assert Ok(_) =
      event_log.append_events(
        db,
        all_events,
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
      )

    // Query for T-001 events using jsonpath filtering
    let #(select_sql, select_params, _decoder) =
      sql.read_events_for_ticket_command_context(ticket_id: "T-001")

    let select_query =
      pog.query(select_sql)
      |> parrot_pog.parameters(select_params)
      |> pog.returning(sql.read_events_for_ticket_command_context_decoder())

    let assert Ok(returned) = pog.execute(select_query, on: db)
    let raw_rows = returned.rows

    // Decode payloads
    let assert Ok(rows) =
      events.decode_ticket_command_context_payloads(
        raw_rows,
        ticket_event.ticket_events_decoder(),
      )

    // Should get exactly 3 events for T-001 (opened, assigned, closed)
    assert list.length(rows) == 3

    // Verify all returned events are for T-001
    let assert [first_event, second_event, third_event] = rows

    // First event should be TicketOpened for T-001
    assert first_event.event_type == "TicketOpened"
    assert first_event.payload == ticket1_opened

    // Second event should be TicketAssigned for T-001
    assert second_event.event_type == "TicketAssigned"
    assert second_event.payload == ticket1_assigned

    // Third event should be TicketClosed for T-001
    assert third_event.event_type == "TicketClosed"
    assert third_event.payload == ticket1_closed
  })
}

pub fn query_events_by_different_ticket_ids_test() {
  test_runner.txn(fn(db) {
    // Create events for multiple tickets (reusing same setup as previous test)
    let ticket1_opened =
      ticket_event.TicketOpened(
        ticket_id: "T-001",
        title: "Fix login bug",
        description: "Users cannot log in",
        priority: "high",
      )

    let ticket2_opened =
      ticket_event.TicketOpened(
        ticket_id: "T-002",
        title: "Update documentation",
        description: "API docs are outdated",
        priority: "medium",
      )

    let test_metadata = ticket_event.create_test_metadata()

    // Store events for both tickets
    let all_events = [ticket1_opened, ticket2_opened]

    let assert Ok(_) =
      event_log.append_events(
        db,
        all_events,
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
      )

    // Query for T-002 events - should get 1 event (TicketOpened only)
    let #(select_sql_t2, select_params_t2, _decoder) =
      sql.read_events_for_ticket_command_context(ticket_id: "T-002")

    let select_query_t2 =
      pog.query(select_sql_t2)
      |> parrot_pog.parameters(select_params_t2)
      |> pog.returning(sql.read_events_for_ticket_command_context_decoder())

    let assert Ok(returned_t2) = pog.execute(select_query_t2, on: db)
    let raw_rows_t2 = returned_t2.rows

    let assert Ok(rows_t2) =
      events.decode_ticket_command_context_payloads(
        raw_rows_t2,
        ticket_event.ticket_events_decoder(),
      )

    // Should get exactly 1 event for T-002
    assert list.length(rows_t2) == 1
    let assert [t2_event] = rows_t2
    assert t2_event.event_type == "TicketOpened"
    assert t2_event.payload == ticket2_opened

    // Query for non-existent ticket - should get 0 events
    let #(select_sql_t999, select_params_t999, _decoder) =
      sql.read_events_for_ticket_command_context(ticket_id: "T-999")

    let select_query_t999 =
      pog.query(select_sql_t999)
      |> parrot_pog.parameters(select_params_t999)
      |> pog.returning(sql.read_events_for_ticket_command_context_decoder())

    let assert Ok(returned_t999) = pog.execute(select_query_t999, on: db)
    let raw_rows_t999 = returned_t999.rows

    let assert Ok(rows_t999) =
      events.decode_ticket_command_context_payloads(
        raw_rows_t999,
        ticket_event.ticket_events_decoder(),
      )

    // Should get 0 events for non-existent ticket
    assert rows_t999 == []
  })
}

pub fn read_events_with_jsonb_path_filter_test() {
  test_runner.txn(fn(db) {
    // Create ticket events with different priorities
    let high_priority_ticket =
      ticket_event.TicketOpened(
        ticket_id: "T-001",
        title: "Critical security bug",
        description: "SQL injection vulnerability",
        priority: "high",
      )

    let medium_priority_ticket =
      ticket_event.TicketOpened(
        ticket_id: "T-002",
        title: "Update documentation",
        description: "User guide needs updating",
        priority: "medium",
      )

    let low_priority_ticket =
      ticket_event.TicketOpened(
        ticket_id: "T-003",
        title: "Minor UI tweak",
        description: "Button color adjustment",
        priority: "low",
      )

    let assigned_event =
      ticket_event.TicketAssigned(
        ticket_id: "T-001",
        assignee: "security-team@example.com",
        assigned_at: "2024-01-15T10:30:00Z",
      )

    let test_metadata = ticket_event.create_test_metadata()

    // Store all events
    let all_events = [
      high_priority_ticket,
      medium_priority_ticket,
      low_priority_ticket,
      assigned_event,
    ]

    let assert Ok(_) =
      event_log.append_events(
        db,
        all_events,
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
      )

    // Create JSONB filter to find TicketOpened events with high priority
    let filters_json =
      event_filter.new()
      |> event_filter.for_type(
        "TicketOpened",
        event_filter.attr_string("priority", "high"),
      )
      |> event_filter.to_string()

    // Execute the filter query
    let #(select_sql, select_params, _decoder) =
      sql.read_events_with_filter(filters: filters_json)

    let select_query =
      pog.query(select_sql)
      |> parrot_pog.parameters(select_params)
      |> pog.returning(sql.read_events_with_filter_decoder())

    let assert Ok(returned) = pog.execute(select_query, on: db)
    let raw_rows = returned.rows

    // Should get exactly 1 event (the high priority TicketOpened)
    assert list.length(raw_rows) == 1

    let assert [filtered_event] = raw_rows
    assert filtered_event.event_type == "TicketOpened"
    assert filtered_event.current_max_sequence > 0

    // Verify it's the high priority ticket by decoding the payload
    let assert Ok(decoded_payload) =
      json.parse(filtered_event.payload, ticket_event.ticket_opened_decoder())
    let assert ticket_event.TicketOpened(ticket_id, _, _, priority) =
      decoded_payload
    assert priority == "high"
    assert ticket_id == "T-001"
  })
}

pub fn multi_filter_conditions_test() {
  test_runner.txn(fn(db) {
    // Create events for multiple tickets with various attributes
    let high_priority_ticket =
      ticket_event.TicketOpened(
        ticket_id: "T-001",
        title: "Critical security bug",
        description: "SQL injection vulnerability",
        priority: "high",
      )

    let medium_priority_ticket =
      ticket_event.TicketOpened(
        ticket_id: "T-002",
        title: "Update documentation",
        description: "User guide needs updating",
        priority: "medium",
      )

    let assignment_t001 =
      ticket_event.TicketAssigned(
        ticket_id: "T-001",
        assignee: "security-team@example.com",
        assigned_at: "2024-01-15T10:30:00Z",
      )

    let assignment_t003 =
      ticket_event.TicketAssigned(
        ticket_id: "T-003",
        assignee: "dev-team@example.com",
        assigned_at: "2024-01-16T09:00:00Z",
      )

    let test_metadata = ticket_event.create_test_metadata()

    // Store all events
    let all_events = [
      high_priority_ticket,
      medium_priority_ticket,
      assignment_t001,
      assignment_t003,
    ]

    let assert Ok(_) =
      event_log.append_events(
        db,
        all_events,
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
      )

    // Create multi-condition filter: high priority TicketOpened OR T-001 TicketAssigned
    let filters_json =
      event_filter.new()
      |> event_filter.for_type(
        "TicketOpened",
        event_filter.attr_string("priority", "high"),
      )
      |> event_filter.for_type(
        "TicketAssigned",
        event_filter.attr_string("ticket_id", "T-001"),
      )
      |> event_filter.to_string()

    // Execute the filter query
    let #(select_sql, select_params, _decoder) =
      sql.read_events_with_filter(filters: filters_json)

    let select_query =
      pog.query(select_sql)
      |> parrot_pog.parameters(select_params)
      |> pog.returning(sql.read_events_with_filter_decoder())

    let assert Ok(returned) = pog.execute(select_query, on: db)
    let raw_rows = returned.rows

    // Should get exactly 2 events: high priority TicketOpened + T-001 TicketAssigned
    assert list.length(raw_rows) == 2

    // Verify we got the expected events
    let event_types = list.map(raw_rows, fn(row) { row.event_type })
    assert list.contains(event_types, "TicketOpened")
    assert list.contains(event_types, "TicketAssigned")

    // Verify specific event contents
    list.each(raw_rows, fn(row) {
      case row.event_type {
        "TicketOpened" -> {
          let assert Ok(decoded) =
            json.parse(row.payload, ticket_event.ticket_opened_decoder())
          let assert ticket_event.TicketOpened(_, _, _, priority) = decoded
          assert priority == "high"
        }
        "TicketAssigned" -> {
          let assert Ok(decoded) =
            json.parse(row.payload, ticket_event.ticket_assigned_decoder())
          let assert ticket_event.TicketAssigned(ticket_id, _, _) = decoded
          assert ticket_id == "T-001"
        }
        _ -> panic as "Unexpected event type"
      }
    })
  })
}

pub fn high_level_query_events_test() {
  test_runner.txn(fn(db) {
    // Create test events
    let high_priority_ticket =
      ticket_event.TicketOpened(
        ticket_id: "T-001",
        title: "Critical bug",
        description: "System crash",
        priority: "high",
      )

    let medium_priority_ticket =
      ticket_event.TicketOpened(
        ticket_id: "T-002",
        title: "Feature request",
        description: "New functionality",
        priority: "medium",
      )

    let assignment =
      ticket_event.TicketAssigned(
        ticket_id: "T-001",
        assignee: "developer@example.com",
        assigned_at: "2024-01-15T10:30:00Z",
      )

    let test_metadata = ticket_event.create_test_metadata()
    let all_events = [high_priority_ticket, medium_priority_ticket, assignment]

    let assert Ok(_) =
      event_log.append_events(
        db,
        all_events,
        ticket_event.ticket_event_to_type_and_payload,
        test_metadata,
      )

    // Create filter for high priority tickets
    let filter =
      event_filter.new()
      |> event_filter.for_type(
        "TicketOpened",
        event_filter.attr_string("priority", "high"),
      )

    // Execute high-level query
    let assert Ok(#(events, max_sequence)) =
      event_log.query_events(db, filter, ticket_event.ticket_event_mapper)

    // Should get 1 high priority ticket
    assert list.length(events) == 1
    assert max_sequence > 0

    // Verify it's the expected event
    let assert [found_event] = events
    let assert ticket_event.TicketOpened(ticket_id, title, _, priority) =
      found_event
    assert ticket_id == "T-001"
    assert title == "Critical bug"
    assert priority == "high"
  })
}
