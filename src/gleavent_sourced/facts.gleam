import gleam/int
import gleam/list
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
  Fact(
    id: int.to_string(unique_integer([])),
    event_filter: event_filter,
    apply_events: apply_events,
  )
}

pub fn event_filter(
  facts: List(Fact(event, context)),
) -> event_filter.EventFilter {
  list.fold(facts, event_filter.new(), fn(filter, fact) {
    event_filter.merge(filter, fact.event_filter)
  })
}

pub fn build_context(facts: List(Fact(event, context))) {
  fn(events: List(event), context) {
    list.fold(facts, context, fn(context, fact) {
      fact.apply_events(context, events)
    })
  }
}

pub fn fold_into(update_context: fn(context, value) -> context, zero: value, apply: fn(value, event) -> value) {
  fn(context, events) {
    list.fold(events, zero, apply) |> update_context(context, _)
  }
}
