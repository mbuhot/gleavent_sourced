import gleam/erlang/process

import gleam/list

import gleavent_sourced/connection_pool
import gleavent_sourced/events
import gleavent_sourced/parrot_pog
import gleavent_sourced/sql
import gleavent_sourced/test_runner
import gleavent_sourced/ticket_events

import pog

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/ticket_events_test"])
}

pub fn store_different_ticket_event_types_test() {
  // Set up database connection pool
  let pool_name = process.new_name("ticket_events_test_pool")
  let assert Ok(_supervisor_pid) = connection_pool.start_supervisor(pool_name)
  let db = pog.named_connection(pool_name)

  // Clear events table for clean test state
  let truncate_query = pog.query("TRUNCATE TABLE events RESTART IDENTITY")
  let assert Ok(_) = pog.execute(truncate_query, on: db)

  // Create test ticket events
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

  let test_metadata = ticket_events.create_test_metadata()

  // Store each event type
  let events = [opened_event, assigned_event, closed_event]

  list.each(events, fn(event) {
    let #(event_type, payload) =
      ticket_events.ticket_event_to_type_and_payload(event)

    let #(insert_sql, insert_params) =
      sql.append_event(
        event_type: event_type,
        payload: payload,
        metadata: test_metadata,
      )

    let insert_query =
      pog.query(insert_sql)
      |> parrot_pog.parameters(insert_params)

    let assert Ok(_) = pog.execute(insert_query, on: db)
  })

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
    events.decode_payloads(raw_rows, ticket_events.ticket_events_decoder())

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
}
