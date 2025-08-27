import gleam/list
import gleam/string
import gleavent_sourced/facts
import gleavent_sourced/event_filter
import gleavent_sourced/test_runner


pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/facts_test"])
}

pub fn new_fact_creates_unique_ids_test() {
  let filter = event_filter.new()
  let apply_fn = fn(context, _events) { context }

  let fact1 = facts.new_fact(filter, apply_fn)
  let fact2 = facts.new_fact(filter, apply_fn)

  assert fact1.id != fact2.id
}

pub fn new_fact_generates_non_empty_id_test() {
  let filter = event_filter.new()
  let apply_fn = fn(context, _events) { context }

  let fact = facts.new_fact(filter, apply_fn)

  assert fact.id != ""
}

pub fn new_fact_preserves_event_filter_test() {
  let filter = event_filter.new()
    |> event_filter.for_type("TestEvent", [])
  let apply_fn = fn(context, _events) { context }

  let fact = facts.new_fact(filter, apply_fn)

  // Verify the core filter content is preserved (fact filter should contain original content plus fact_id tag)
  let _original_filter_string = event_filter.to_string(filter)
  let fact_filter_string = event_filter.to_string(fact.event_filter)

  // The fact filter should contain all the original filter content
  let assert True = string.contains(fact_filter_string, "\"event_type\":\"TestEvent\"")
  let assert True = string.contains(fact_filter_string, "\"filter\":\"$ ? (true)\"")
  let assert True = string.contains(fact_filter_string, "\"params\":{}")
  // Plus the fact_id tag
  let assert True = string.contains(fact_filter_string, "\"fact_id\"")
  let assert True = string.contains(fact_filter_string, "\"" <> fact.id <> "\"")
}

pub fn multiple_facts_have_different_ids_test() {
  let filter = event_filter.new()
  let apply_fn = fn(context, _events) { context }

  let facts_list = list.range(1, 5)
    |> list.map(fn(_) { facts.new_fact(filter, apply_fn) })
  let ids = list.map(facts_list, fn(fact) { fact.id })

  // All IDs should be unique - convert to set and check length
  let unique_ids = list.unique(ids)
  assert list.length(unique_ids) == 5
}

pub fn new_fact_automatically_tags_filter_with_id_test() {
  let filter = event_filter.new()
    |> event_filter.for_type("TicketOpened", [
      event_filter.attr_string("ticket_id", "T-100")
    ])
  let apply_fn = fn(context, _events) { context }

  let fact = facts.new_fact(filter, apply_fn)
  let filter_json_string = event_filter.to_string(fact.event_filter)

  // The filter should be tagged with the fact's ID
  // Check that the JSON contains the fact_id field
  let assert True = string.contains(filter_json_string, "\"fact_id\"")
  let assert True = string.contains(filter_json_string, "\"" <> fact.id <> "\"")
}

// Mock event type for testing event isolation
pub type TestEvent {
  TicketOpened(ticket_id: String, title: String)
  TicketClosed(ticket_id: String)
  TicketAssigned(ticket_id: String, assignee: String)
}

// Mock context type for testing
pub type TestContext {
  TestContext(
    ticket_a_opened: Bool,
    ticket_a_closed: Bool,
    ticket_b_opened: Bool,
    ticket_b_closed: Bool,
    events_received_by_fact_a: List(TestEvent),
    events_received_by_fact_b: List(TestEvent),
  )
}

pub fn build_context_currently_gives_all_events_to_all_facts_test() {
  // This test demonstrates the CURRENT problem: all facts receive all events
  // even when they should only process events matching their filter

  let fact_a = facts.new_fact(
    event_filter: event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "A-100")
      ]),
    apply_events: fn(context: TestContext, events: List(TestEvent)) {
      // Fact A should only see TicketOpened events for A-100
      TestContext(
        ..context,
        events_received_by_fact_a: list.append(context.events_received_by_fact_a, events)
      )
    }
  )

  let fact_b = facts.new_fact(
    event_filter: event_filter.new()
      |> event_filter.for_type("TicketClosed", [
        event_filter.attr_string("ticket_id", "B-200")
      ]),
    apply_events: fn(context: TestContext, events: List(TestEvent)) {
      // Fact B should only see TicketClosed events for B-200
      TestContext(
        ..context,
        events_received_by_fact_b: list.append(context.events_received_by_fact_b, events)
      )
    }
  )

  let events = [
    TicketOpened("A-100", "Bug in login"),     // Should go to fact_a only
    TicketClosed("B-200"),                     // Should go to fact_b only
    TicketOpened("C-300", "Feature request"), // Should go to neither
    TicketAssigned("A-100", "alice"),         // Should go to neither
  ]

  let initial_context = TestContext(
    ticket_a_opened: False,
    ticket_a_closed: False,
    ticket_b_opened: False,
    ticket_b_closed: False,
    events_received_by_fact_a: [],
    events_received_by_fact_b: [],
  )

  let context_builder = facts.build_context([fact_a, fact_b])
  let final_context = context_builder(events, initial_context)

  // CURRENT BROKEN BEHAVIOR: Each fact receives ALL events, not just matching ones
  // This shows the problem we're trying to solve
  let assert True = list.length(final_context.events_received_by_fact_a) == list.length(events)
  let assert True = list.length(final_context.events_received_by_fact_b) == list.length(events)

  // Both facts get the same events - this is the duplication problem
  assert final_context.events_received_by_fact_a == final_context.events_received_by_fact_b
}

pub fn build_context_with_tagged_sql_queries_test() {
  // This test demonstrates that facts are created with auto-generated IDs and tagged filters
  // The SQL-level tagging system will use these IDs to route events correctly
  // This test verifies the structure is correct for SQL integration

  let fact_a = facts.new_fact(
    event_filter: event_filter.new()
      |> event_filter.for_type("TicketOpened", [
        event_filter.attr_string("ticket_id", "A-100")
      ]),
    apply_events: fn(context: TestContext, events: List(TestEvent)) {
      // Each fact will only receive events matching its filter from SQL query
      let a_events = list.append(context.events_received_by_fact_a, events)
      TestContext(
        ..context,
        ticket_a_opened: case list.any(events, fn(e) {
          case e { TicketOpened("A-100", _) -> True _ -> False }
        }) {
          True -> True
          False -> context.ticket_a_opened
        },
        events_received_by_fact_a: a_events,
      )
    }
  )

  let fact_b = facts.new_fact(
    event_filter: event_filter.new()
      |> event_filter.for_type("TicketClosed", [
        event_filter.attr_string("ticket_id", "B-200")
      ]),
    apply_events: fn(context: TestContext, events: List(TestEvent)) {
      let b_events = list.append(context.events_received_by_fact_b, events)
      TestContext(
        ..context,
        ticket_b_closed: case list.any(events, fn(e) {
          case e { TicketClosed("B-200") -> True _ -> False }
        }) {
          True -> True
          False -> context.ticket_b_closed
        },
        events_received_by_fact_b: b_events,
      )
    }
  )

  // Verify facts have unique IDs and tagged filters
  assert fact_a.id != fact_b.id

  // Verify filters are tagged with fact IDs (for SQL query)
  let fact_a_filter_json = event_filter.to_string(fact_a.event_filter)
  let fact_b_filter_json = event_filter.to_string(fact_b.event_filter)

  assert string.contains(fact_a_filter_json, "\"fact_id\":\"" <> fact_a.id <> "\"")
  assert string.contains(fact_b_filter_json, "\"fact_id\":\"" <> fact_b.id <> "\"")

  // Verify each filter contains the expected event type and ticket_id in params
  assert string.contains(fact_a_filter_json, "\"event_type\":\"TicketOpened\"")
  assert string.contains(fact_a_filter_json, "\"A-100\"")
  assert string.contains(fact_b_filter_json, "\"event_type\":\"TicketClosed\"")
  assert string.contains(fact_b_filter_json, "\"B-200\"")
}
