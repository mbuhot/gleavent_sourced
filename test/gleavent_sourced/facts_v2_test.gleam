import gleam/dict
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/event_filter
import gleavent_sourced/event_log
import gleavent_sourced/facts_v2
import gleavent_sourced/test_runner
import pog

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/facts_v2_test"])
}

pub type TestContext {
  TestContext(value: Int)
}

pub type IntegrationTestContext {
  IntegrationTestContext(
    ticket_exists: Bool,
    ticket_closed: Bool,
    ticket_priority: String,
  )
}

pub fn create_test_metadata() -> dict.Dict(String, String) {
  dict.from_list([
    #("source", "facts_v2_integration_test"),
    #("version", "1"),
  ])
}

pub fn empty_facts_list_handles_gracefully_test() {
  let composed = facts_v2.compose_facts([])

  // Should return exact empty query
  let expected_sql =
    "SELECT NULL as fact_id, sequence_number, event_type, payload, metadata, 0 as max_sequence_number "
    <> "FROM events WHERE false"

  assert composed.sql == expected_sql
  assert composed.params == []
}

pub fn different_parameter_counts_composition_test() {
  // Test facts with 0, 1, and 3 parameters to verify dynamic adjustment

  // Fact with no parameters
  let no_param_fact =
    facts_v2.new_fact(
      sql: "SELECT * FROM events e WHERE e.event_type = 'TicketOpened'",
      params: [],
      apply_events: fn(context, _events) { context },
    )

  // Fact with 1 parameter
  let one_param_fact =
    facts_v2.new_fact(
      sql: "SELECT * FROM events e WHERE e.payload @> jsonb_build_object('ticket_id', $1)",
      params: [pog.text("T-100")],
      apply_events: fn(context, _events) { context },
    )

  // Fact with 3 parameters
  let three_param_fact =
    facts_v2.new_fact(
      sql: "SELECT * FROM events e WHERE e.payload @> jsonb_build_object('ticket_id', $1) AND e.event_type = $2 AND e.payload @> jsonb_build_object('priority', $3)",
      params: [pog.text("T-100"), pog.text("TicketOpened"), pog.text("high")],
      apply_events: fn(context, _events) { context },
    )

  let composed =
    facts_v2.compose_facts([no_param_fact, one_param_fact, three_param_fact])

  // Should generate exact SQL with correct parameter adjustments
  let expected_sql =
    "WITH fact_1 AS ("
    <> "SELECT 'fact_1' as fact_id, user_query.sequence_number, user_query.event_type, "
    <> "user_query.payload, user_query.metadata "
    <> "FROM (SELECT * FROM events e WHERE e.event_type = 'TicketOpened') user_query), "
    <> "fact_2 AS ("
    <> "SELECT 'fact_2' as fact_id, user_query.sequence_number, user_query.event_type, "
    <> "user_query.payload, user_query.metadata "
    <> "FROM (SELECT * FROM events e WHERE e.payload @> jsonb_build_object('ticket_id', $1)) "
    <> "user_query), "
    <> "fact_3 AS ("
    <> "SELECT 'fact_3' as fact_id, user_query.sequence_number, user_query.event_type, "
    <> "user_query.payload, user_query.metadata "
    <> "FROM (SELECT * FROM events e WHERE e.payload @> jsonb_build_object('ticket_id', $2) "
    <> "AND e.event_type = $3 AND e.payload @> jsonb_build_object('priority', $4)) user_query), "
    <> "all_events AS (SELECT * FROM fact_1 UNION ALL SELECT * FROM fact_2 UNION ALL "
    <> "SELECT * FROM fact_3) "
    <> "SELECT all_events.*, MAX(all_events.sequence_number) OVER () as max_sequence_number "
    <> "FROM all_events ORDER BY all_events.sequence_number"

  assert composed.sql == expected_sql
  assert composed.params
    == [
      pog.text("T-100"),
      pog.text("T-100"),
      pog.text("TicketOpened"),
      pog.text("high"),
    ]
}

pub fn complex_sql_with_subqueries_test() {
  // Test that subquery wrapping works correctly with complex SQL containing subqueries
  let complex_fact =
    facts_v2.new_fact(
      sql: "SELECT e.* FROM events e WHERE e.ticket_id IN (SELECT ticket_id FROM events sub WHERE sub.event_type = 'TicketOpened' AND sub.payload @> jsonb_build_object('priority', $1)) AND EXISTS (SELECT 1 FROM events related WHERE related.event_type = 'TicketAssigned' AND related.ticket_id = e.ticket_id)",
      params: [pog.text("high")],
      apply_events: fn(context, _events) { context },
    )

  let simple_fact =
    facts_v2.new_fact(
      sql: "SELECT * FROM events e WHERE e.event_type = $1",
      params: [pog.text("TicketClosed")],
      apply_events: fn(context, _events) { context },
    )

  let composed = facts_v2.compose_facts([complex_fact, simple_fact])

  // Should generate exact SQL preserving complex subqueries
  let expected_sql =
    "WITH fact_1 AS ("
    <> "SELECT 'fact_1' as fact_id, user_query.sequence_number, user_query.event_type, "
    <> "user_query.payload, user_query.metadata "
    <> "FROM (SELECT e.* FROM events e WHERE e.ticket_id IN "
    <> "(SELECT ticket_id FROM events sub WHERE sub.event_type = 'TicketOpened' "
    <> "AND sub.payload @> jsonb_build_object('priority', $1)) "
    <> "AND EXISTS (SELECT 1 FROM events related WHERE related.event_type = 'TicketAssigned' "
    <> "AND related.ticket_id = e.ticket_id)) user_query), "
    <> "fact_2 AS ("
    <> "SELECT 'fact_2' as fact_id, user_query.sequence_number, user_query.event_type, "
    <> "user_query.payload, user_query.metadata "
    <> "FROM (SELECT * FROM events e WHERE e.event_type = $2) user_query), "
    <> "all_events AS (SELECT * FROM fact_1 UNION ALL SELECT * FROM fact_2) "
    <> "SELECT all_events.*, MAX(all_events.sequence_number) OVER () as max_sequence_number "
    <> "FROM all_events ORDER BY all_events.sequence_number"

  assert composed.sql == expected_sql
  assert composed.params == [pog.text("high"), pog.text("TicketClosed")]
}

pub fn end_to_end_database_integration_test() {
  // Integration test: insert real events with event_log, read back with facts_v2
  test_runner.txn(fn(db) {
    let test_metadata = create_test_metadata()

    // Insert real events using existing event_log module
    let events = [
      ticket_events.TicketOpened(
        ticket_id: "T-123",
        title: "Integration test ticket",
        description: "Testing facts_v2 with real data",
        priority: "high",
      ),
      ticket_events.TicketAssigned(
        ticket_id: "T-123",
        assignee: "alice@company.com",
        assigned_at: "2024-01-15T10:30:00Z",
      ),
      ticket_events.TicketClosed(
        ticket_id: "T-123",
        resolution: "completed",
        closed_at: "2024-01-15T11:00:00Z",
      ),
    ]

    let assert Ok(event_log.AppendSuccess) =
      event_log.append_events(
        db,
        events,
        ticket_events.encode,
        test_metadata,
        event_filter.new(),
        0,
      )

    // Create facts to read the data back
    let ticket_exists_fact =
      facts_v2.new_fact(
        sql: "SELECT * FROM events e WHERE e.event_type = 'TicketOpened' AND e.payload @> jsonb_build_object('ticket_id', $1::text)",
        params: [pog.text("T-123")],
        apply_events: fn(context: IntegrationTestContext, events) {
          let exists = case events {
            [] -> False
            _ -> True
          }
          IntegrationTestContext(..context, ticket_exists: exists)
        },
      )

    let ticket_closed_fact =
      facts_v2.new_fact(
        sql: "SELECT * FROM events e WHERE e.event_type = 'TicketClosed' AND e.payload @> jsonb_build_object('ticket_id', $1::text)",
        params: [pog.text("T-123")],
        apply_events: fn(context: IntegrationTestContext, events) {
          let closed = case events {
            [] -> False
            _ -> True
          }
          IntegrationTestContext(..context, ticket_closed: closed)
        },
      )

    let ticket_priority_fact =
      facts_v2.new_fact(
        sql: "SELECT * FROM events e WHERE e.event_type = 'TicketOpened' AND e.payload @> jsonb_build_object('ticket_id', $1::text)",
        params: [pog.text("T-123")],
        apply_events: fn(context: IntegrationTestContext, events) {
          let priority = case events {
            [] -> "unknown"
            [ticket_events.TicketOpened(_, _, _, priority), ..] -> priority
            _ -> "unknown"
          }
          IntegrationTestContext(..context, ticket_priority: priority)
        },
      )

    let facts = [ticket_exists_fact, ticket_closed_fact, ticket_priority_fact]

    // Query using facts_v2 system
    let initial_context =
      IntegrationTestContext(
        ticket_exists: False,
        ticket_closed: False,
        ticket_priority: "unknown",
      )

    let assert Ok(final_context) =
      facts_v2.query_event_log(db, facts, initial_context, ticket_events.decode)

    // Verify the context was built correctly from real database events
    assert final_context.ticket_exists == True
    assert final_context.ticket_closed == True
    assert final_context.ticket_priority == "high"
  })
}
