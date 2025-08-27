import gleam/list
import gleam/option.{type Option, Some, None}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/event_filter

// Core fact abstraction - represents a domain concept derived from events
pub type Fact(value, event, context) {
  Fact(
    event_filter: event_filter.EventFilter,
    reducer: fn(List(event), value) -> value,
    initial_value: value,
    update_context: fn(context, value) -> context,
  )
}

// Union type for all ticket-related facts
pub type TicketFact(context) {
  TicketExists(Fact(Bool, TicketEvent, context))
  TicketClosed(Fact(Bool, TicketEvent, context))
  TicketAssignee(Fact(Option(String), TicketEvent, context))
  TicketPriority(Fact(Option(String), TicketEvent, context))
}

pub fn event_filter(
  facts: List(TicketFact(context)),
) -> event_filter.EventFilter {
  list.fold(facts, event_filter.new(), fn(filter, fact) {
    case fact {
      TicketAssignee(f) -> event_filter.merge(filter, f.event_filter)
      TicketClosed(f) -> event_filter.merge(filter, f.event_filter)
      TicketExists(f) -> event_filter.merge(filter, f.event_filter)
      TicketPriority(f) -> event_filter.merge(filter, f.event_filter)
    }
  })
}

pub fn eval(
  events: List(TicketEvent),
  context,
  tf: TicketFact(context),
) -> context {
  case tf {
    TicketExists(f) -> do_eval(events, context, f)
    TicketClosed(f) -> do_eval(events, context, f)
    TicketAssignee(f) -> do_eval(events, context, f)
    TicketPriority(f) -> do_eval(events, context, f)
  }
}

fn do_eval(events: List(event), c: context, fact: Fact(_, event, context)) {
  fact.reducer(events, fact.initial_value) |> fact.update_context(c, _)
}

pub fn build_context(facts: List(TicketFact(context))) {
  fn(events: List(TicketEvent), context) {
    list.fold(facts, context, fn(context, fact) { eval(events, context, fact) })
  }
}

fn for_type_with_id(event_type, ticket_id) {
  event_filter.new()
  |> event_filter.for_type(event_type, [
    event_filter.attr_string("ticket_id", ticket_id),
  ])
}

fn reducer(apply) {
  fn(events, initial_value) {
    list.fold(events, initial_value, apply)
  }
}

// Fact: Whether a ticket exists (derived from TicketOpened)
pub fn exists(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> TicketFact(context) {
  TicketExists(Fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    reducer: reducer(fn(acc, event) {
        case event {
          ticket_events.TicketOpened(..) -> True
          _ -> acc
        }
      }),
    initial_value: False,
    update_context: update_context,
  ))
}

// Fact: Whether a ticket is closed (derived from TicketClosed)
pub fn is_closed(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> TicketFact(context) {
  TicketClosed(Fact(
    event_filter: for_type_with_id("TicketClosed", ticket_id),
    reducer: reducer(fn(acc, event) {
        case event {
          ticket_events.TicketClosed(..) -> True
          _ -> acc
        }
      }),
    initial_value: False,
    update_context: update_context,
  ))
}

// Fact: Current assignee of ticket (derived from TicketAssigned)
pub fn current_assignee(
  ticket_id: String,
  update_context: fn(context, Option(String)) -> context,
) -> TicketFact(context) {
  TicketAssignee(Fact(
    event_filter: for_type_with_id("TicketAssigned", ticket_id),
    reducer: reducer(fn(acc, event) {
        case event {
          ticket_events.TicketAssigned(_, assignee, _) -> Some(assignee)
          _ -> acc
        }
      }),
    initial_value: None,
    update_context: update_context,
  ))
}

// Fact: Priority of ticket (derived from TicketOpened)
pub fn priority(
  ticket_id: String,
  update_context: fn(context, Option(String)) -> context,
) -> TicketFact(context) {
  TicketPriority(Fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    reducer: reducer(fn(acc, event) {
        case event {
          ticket_events.TicketOpened(_, _, _, priority) -> Some(priority)
          _ -> acc
        }
      }),
    initial_value: None,
    update_context: update_context,
  ))
}
