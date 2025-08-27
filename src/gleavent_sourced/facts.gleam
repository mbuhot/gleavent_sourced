import gleam/dict

import gleam/int
import gleam/list
import gleam/result

import gleavent_sourced/event_filter

@external(erlang, "erlang", "unique_integer")
fn unique_integer(options: List(a)) -> Int

// Core fact abstraction - represents a domain concept derived from events
pub type Fact(event, context) {
  Fact(
    id: String,
    event_filter: event_filter.EventFilter,
    apply_events: fn(context, List(event)) -> context,
  )
}

// Constructor to create a new Fact with auto-generated unique ID
pub fn new_fact(
  event_filter event_filter: event_filter.EventFilter,
  apply_events apply_events: fn(context, List(event)) -> context,
) -> Fact(event, context) {
  let id = int.to_string(unique_integer([]))
  let tagged_filter = event_filter.with_tag(event_filter, id)
  Fact(id: id, event_filter: tagged_filter, apply_events: apply_events)
}

pub fn event_filter(
  facts: List(Fact(event, context)),
) -> event_filter.EventFilter {
  list.fold(facts, event_filter.new(), fn(filter, fact) {
    event_filter.merge(filter, fact.event_filter)
  })
}

pub fn build_context(facts: List(Fact(event, context))) {
  fn(events_by_fact: dict.Dict(String, List(event)), context) {
    // Route events to facts based on their IDs as keys in the dict
    list.fold(facts, context, fn(acc_context, fact) {
      let fact_events = dict.get(events_by_fact, fact.id) |> result.unwrap([])
      fact.apply_events(acc_context, fact_events)
    })
  }
}

pub fn fold_into(
  update_context: fn(context, value) -> context,
  zero: value,
  apply: fn(value, event) -> value,
) {
  fn(context, events) {
    list.fold(events, zero, apply) |> update_context(context, _)
  }
}
