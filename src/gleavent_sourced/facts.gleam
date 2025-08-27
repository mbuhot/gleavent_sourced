import gleam/list
import gleavent_sourced/event_filter

// Core fact abstraction - represents a domain concept derived from events
pub type Fact(event, context) {
  Fact(
    event_filter: event_filter.EventFilter,
    apply_events: fn(context, List(event)) -> context,
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
