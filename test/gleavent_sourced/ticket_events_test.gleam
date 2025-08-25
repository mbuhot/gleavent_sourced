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
        event_filter.new(),
        0,
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
        event_filter.new(),
        0,
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
        event_filter.new(),
        0,
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
        event_filter.new(),
        0,
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
        event_filter.new(),
        0,
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

pub fn successful_batch_insert_no_conflicts_test() {
  test_runner.txn(fn(db) {
    // Create test events
    let opened_event = ticket_event.TicketOpened(
      ticket_id: "T-001",
      title: "Test ticket",
      description: "A test ticket for batch insert",
      priority: "medium"
    )
    let assigned_event = ticket_event.TicketAssigned(
      ticket_id: "T-001",
      assignee: "developer@example.com",
      assigned_at: "2024-01-01T10:00:00Z"
    )
    let events = [opened_event, assigned_event]
    let test_metadata = ticket_event.create_test_metadata()

    // Create empty conflict filter (should never conflict)
    let empty_filter = event_filter.new()

    // Append events with optimistic concurrency control
    let result = event_log.append_events(
      db,
      events,
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      empty_filter,
      0,  // last_seen_sequence = 0 (no conflicts expected)
    )

    // Should succeed with no conflicts
    let assert Ok(event_log.AppendSuccess) = result

    // Verify events were actually inserted by querying them back for T-001
    let #(select_sql, select_params, decoder) = sql.read_events_for_ticket_command_context(ticket_id: "T-001")
    let select_query =
      pog.query(select_sql)
      |> parrot_pog.parameters(select_params)
      |> pog.returning(decoder)

    let assert Ok(returned) = pog.execute(select_query, on: db)
    let rows = returned.rows

    // Should have exactly 2 events for T-001
    let assert 2 = list.length(rows)

    // Verify event types
    let event_types = list.map(rows, fn(row) { row.event_type })
    let assert True = list.contains(event_types, "TicketOpened")
    let assert True = list.contains(event_types, "TicketAssigned")

    Nil
  })
}

pub fn conflict_detection_events_added_since_last_read_test() {
  test_runner.txn(fn(db) {
    // Step 1: Insert initial events
    let initial_event = ticket_event.TicketOpened(
      ticket_id: "T-002",
      title: "Initial ticket",
      description: "This ticket was opened first",
      priority: "low"
    )
    let test_metadata = ticket_event.create_test_metadata()

    let assert Ok(event_log.AppendSuccess) = event_log.append_events(
      db,
      [initial_event],
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      event_filter.new(),
      0,
    )

    // Step 2: Query to get current sequence number
    let #(select_sql, select_params, decoder) = sql.read_events_for_ticket_command_context(ticket_id: "T-002")
    let select_query =
      pog.query(select_sql)
      |> parrot_pog.parameters(select_params)
      |> pog.returning(decoder)

    let assert Ok(returned) = pog.execute(select_query, on: db)
    let rows = returned.rows
    let assert [first_event] = rows
    let last_seen_sequence = first_event.sequence_number

    // Step 3: Insert a conflicting event (simulates another process adding events)
    let conflicting_event = ticket_event.TicketAssigned(
      ticket_id: "T-002",
      assignee: "another-process@example.com",
      assigned_at: "2024-01-01T11:00:00Z"
    )

    let assert Ok(event_log.AppendSuccess) = event_log.append_events(
      db,
      [conflicting_event],
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      event_filter.new(),
      0,  // Use 0 to bypass conflict check for this insert
    )

    // Step 4: Try to insert new events with outdated sequence number and conflicting filter
    let new_event = ticket_event.TicketClosed(
      ticket_id: "T-002",
      resolution: "Fixed the issue",
      closed_at: "2024-01-01T12:00:00Z"
    )

    // Create conflict filter that would match the TicketAssigned event
    let conflict_filter =
      event_filter.new()
      |> event_filter.for_type("TicketAssigned", event_filter.attr_string("ticket_id", "T-002"))

    // This should detect conflict because TicketAssigned was added after last_seen_sequence
    let result = event_log.append_events(
      db,
      [new_event],
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      conflict_filter,
      last_seen_sequence,
    )

    // Should return conflict with count of 1
    let assert Ok(event_log.AppendConflict(conflict_count: 1)) = result

    // Verify the conflicting event was NOT inserted by checking final count
    let #(final_sql, final_params, final_decoder) = sql.read_events_for_ticket_command_context(ticket_id: "T-002")
    let final_query =
      pog.query(final_sql)
      |> parrot_pog.parameters(final_params)
      |> pog.returning(final_decoder)

    let assert Ok(final_returned) = pog.execute(final_query, on: db)
    let final_rows = final_returned.rows

    // Should still have only 2 events (initial + conflicting), not 3
    let assert 2 = list.length(final_rows)

    Nil
  })
}

pub fn empty_events_list_with_conflict_filter_test() {
  test_runner.txn(fn(db) {
    // Step 1: Insert some existing events that would match our conflict filter
    let existing_event = ticket_event.TicketOpened(
      ticket_id: "T-003",
      title: "Existing ticket",
      description: "This ticket exists before our empty append",
      priority: "high"
    )
    let test_metadata = ticket_event.create_test_metadata()

    let assert Ok(event_log.AppendSuccess) = event_log.append_events(
      db,
      [existing_event],
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      event_filter.new(),
      0,
    )

    // Step 2: Get the sequence number after the existing event
    let #(select_sql, select_params, decoder) = sql.read_events_for_ticket_command_context(ticket_id: "T-003")
    let select_query =
      pog.query(select_sql)
      |> parrot_pog.parameters(select_params)
      |> pog.returning(decoder)

    let assert Ok(returned) = pog.execute(select_query, on: db)
    let rows = returned.rows
    let assert [first_event] = rows
    let last_seen_sequence = first_event.sequence_number

    // Step 3: Try to append empty list with a conflict filter that matches existing events
    let conflict_filter =
      event_filter.new()
      |> event_filter.for_type("TicketOpened", event_filter.attr_string("ticket_id", "T-003"))

    let result = event_log.append_events(
      db,
      [],  // Empty events list
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      conflict_filter,
      last_seen_sequence,
    )

    // Should return conflict with 0 count because no events were inserted
    let assert Ok(event_log.AppendConflict(conflict_count: 0)) = result

    // Step 4: Verify no additional events were added
    let #(final_sql, final_params, final_decoder) = sql.read_events_for_ticket_command_context(ticket_id: "T-003")
    let final_query =
      pog.query(final_sql)
      |> parrot_pog.parameters(final_params)
      |> pog.returning(final_decoder)

    let assert Ok(final_returned) = pog.execute(final_query, on: db)
    let final_rows = final_returned.rows

    // Should still have only 1 event (the original)
    let assert 1 = list.length(final_rows)

    Nil
  })
}

pub fn all_or_nothing_batch_behavior_test() {
  test_runner.txn(fn(db) {
    // Step 1: Insert an existing event that will cause conflicts
    let existing_event = ticket_event.TicketOpened(
      ticket_id: "T-004",
      title: "Existing ticket",
      description: "This ticket exists and will cause conflicts",
      priority: "medium"
    )
    let test_metadata = ticket_event.create_test_metadata()

    let assert Ok(event_log.AppendSuccess) = event_log.append_events(
      db,
      [existing_event],
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      event_filter.new(),
      0,
    )

    // Step 2: Get the sequence number after the existing event
    let #(select_sql, select_params, decoder) = sql.read_events_for_ticket_command_context(ticket_id: "T-004")
    let select_query =
      pog.query(select_sql)
      |> parrot_pog.parameters(select_params)
      |> pog.returning(decoder)

    let assert Ok(returned) = pog.execute(select_query, on: db)
    let rows = returned.rows
    let assert [first_event] = rows
    let last_seen_sequence = first_event.sequence_number

    // Step 3: Insert another conflicting event (simulates concurrent modification)
    let conflicting_event = ticket_event.TicketAssigned(
      ticket_id: "T-004",
      assignee: "concurrent-user@example.com",
      assigned_at: "2024-01-01T11:30:00Z"
    )

    let assert Ok(event_log.AppendSuccess) = event_log.append_events(
      db,
      [conflicting_event],
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      event_filter.new(),
      0,  // Bypass conflict check for this insert
    )

    // Step 4: Try to insert a batch with mixed conflicts
    // - One event for T-004 (would conflict with TicketAssigned)
    // - One event for T-999 (would not conflict)
    let batch_events = [
      ticket_event.TicketClosed(
        ticket_id: "T-004",
        resolution: "Fixed the T-004 issue",
        closed_at: "2024-01-01T12:00:00Z"
      ),
      ticket_event.TicketOpened(
        ticket_id: "T-999",
        title: "Unrelated ticket",
        description: "This ticket should not conflict",
        priority: "low"
      )
    ]

    // Create conflict filter that matches T-004 TicketAssigned events
    let conflict_filter =
      event_filter.new()
      |> event_filter.for_type("TicketAssigned", event_filter.attr_string("ticket_id", "T-004"))

    let result = event_log.append_events(
      db,
      batch_events,
      ticket_event.ticket_event_to_type_and_payload,
      test_metadata,
      conflict_filter,
      last_seen_sequence,
    )

    // Should return conflict - ALL events are rejected, even the non-conflicting T-999 event
    let assert Ok(event_log.AppendConflict(conflict_count: 1)) = result

    // Step 5: Verify NO events from the batch were inserted
    // Check T-004 still has only 2 events (original + conflicting)
    let #(t004_sql, t004_params, t004_decoder) = sql.read_events_for_ticket_command_context(ticket_id: "T-004")
    let t004_query =
      pog.query(t004_sql)
      |> parrot_pog.parameters(t004_params)
      |> pog.returning(t004_decoder)

    let assert Ok(t004_returned) = pog.execute(t004_query, on: db)
    let t004_rows = t004_returned.rows
    let assert 2 = list.length(t004_rows)  // Still only original + conflicting

    // Check T-999 has 0 events (the non-conflicting event was also rejected)
    let #(t999_sql, t999_params, t999_decoder) = sql.read_events_for_ticket_command_context(ticket_id: "T-999")
    let t999_query =
      pog.query(t999_sql)
      |> parrot_pog.parameters(t999_params)
      |> pog.returning(t999_decoder)

    let assert Ok(t999_returned) = pog.execute(t999_query, on: db)
    let t999_rows = t999_returned.rows
    let assert 0 = list.length(t999_rows)  // No events inserted due to all-or-nothing behavior

    Nil
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
        event_filter.new(),
        0,
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
