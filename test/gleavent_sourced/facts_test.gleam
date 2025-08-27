import gleam/list
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

  // Verify the filter is preserved by converting to string
  let original_filter_string = event_filter.to_string(filter)
  let fact_filter_string = event_filter.to_string(fact.event_filter)

  assert fact_filter_string == original_filter_string
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
