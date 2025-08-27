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
