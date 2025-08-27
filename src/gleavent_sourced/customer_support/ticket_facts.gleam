import gleam/list
import gleam/option.{type Option, None, Some}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/event_filter
import gleavent_sourced/facts

fn for_type_with_id(event_type, ticket_id) {
  event_filter.new()
  |> event_filter.for_type(event_type, [
    event_filter.attr_string("ticket_id", ticket_id),
  ])
}

fn fold_into(update_context, zero, apply) {
  fn(context, events) {
    list.fold(events, zero, apply) |> update_context(context, _)
  }
}

// Fact: Whether a ticket exists (derived from TicketOpened)
pub fn exists(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.Fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    apply_events: fold_into(update_context, False, fn(acc, event) {
      case event {
        ticket_events.TicketOpened(..) -> True
        _ -> acc
      }
    }),
  )
}

// Fact: Whether a ticket is closed (derived from TicketClosed)
pub fn is_closed(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.Fact(
    event_filter: for_type_with_id("TicketClosed", ticket_id),
    apply_events: fold_into(update_context, False, fn(acc, event) {
      case event {
        ticket_events.TicketClosed(..) -> True
        _ -> acc
      }
    }),
  )
}

// Fact: Current assignee of ticket (derived from TicketAssigned)
pub fn current_assignee(
  ticket_id: String,
  update_context: fn(context, Option(String)) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.Fact(
    event_filter: for_type_with_id("TicketAssigned", ticket_id),
    apply_events: fold_into(update_context, None, fn(acc, event) {
      case event {
        ticket_events.TicketAssigned(_, assignee, _) -> Some(assignee)
        _ -> acc
      }
    }),
  )
}

// Fact: Priority of ticket (derived from TicketOpened)
pub fn priority(
  ticket_id: String,
  update_context: fn(context, Option(String)) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.Fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    apply_events: fold_into(update_context, None, fn(acc, event) {
      case event {
        ticket_events.TicketOpened(_, _, _, priority) -> Some(priority)
        _ -> acc
      }
    }),
  )
}
