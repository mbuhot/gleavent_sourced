import gleam/option.{type Option, None, Some}
import gleavent_sourced/customer_support/ticket_events.{
  type TicketEvent, TicketAssigned, TicketClosed, TicketMarkedDuplicate,
  TicketOpened,
}
import gleavent_sourced/event_filter
import gleavent_sourced/facts

pub type DuplicateStatus {
  Unique
  DuplicateOf(original_ticket_id: String)
  DuplicatedBy(duplicate_ticket_id: String)
}

fn for_type_with_id(event_type, ticket_id) {
  event_filter.new()
  |> event_filter.for_type(event_type, [
    event_filter.attr_string("ticket_id", ticket_id),
  ])
}

// Fact: Whether a ticket exists (derived from TicketOpened)
pub fn exists(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.new_fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    apply_events: facts.fold_into(update_context, False, fn(_acc, event) {
      let assert TicketOpened(..) = event
      True
    }),
  )
}

// Fact: Whether a ticket is closed (derived from TicketClosed)
pub fn is_closed(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.new_fact(
    event_filter: for_type_with_id("TicketClosed", ticket_id),
    apply_events: facts.fold_into(update_context, False, fn(_acc, event) {
      let assert TicketClosed(..) = event
      True
    }),
  )
}

// Fact: Current assignee of ticket (derived from TicketAssigned)
pub fn current_assignee(
  ticket_id: String,
  update_context: fn(context, Option(String)) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.new_fact(
    event_filter: for_type_with_id("TicketAssigned", ticket_id),
    apply_events: facts.fold_into(update_context, None, fn(_acc, event) {
      let assert TicketAssigned(_, assignee, _) = event
      Some(assignee)
    }),
  )
}

// Fact: Priority of ticket (derived from TicketOpened)
pub fn priority(
  ticket_id: String,
  update_context: fn(context, Option(String)) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.new_fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    apply_events: facts.fold_into(update_context, None, fn(_acc, event) {
      let assert TicketOpened(_, _, _, priority) = event
      Some(priority)
    }),
  )
}

// Fact: Duplicate status of ticket (derived from TicketMarkedDuplicate)
// Returns status indicating if ticket is unique, duplicate of another, or has duplicates
pub fn duplicate_status(
  ticket_id: String,
  update_context: fn(context, DuplicateStatus) -> context,
) -> facts.Fact(TicketEvent, context) {
  let event_filter =
    event_filter.new()
    |> event_filter.for_type("TicketMarkedDuplicate", [
      event_filter.attr_string("duplicate_ticket_id", ticket_id),
    ])
    |> event_filter.for_type("TicketMarkedDuplicate", [
      event_filter.attr_string("original_ticket_id", ticket_id),
    ])

  facts.new_fact(
    event_filter: event_filter,
    apply_events: facts.fold_into(update_context, Unique, fn(_acc, event) {
      let assert TicketMarkedDuplicate(duplicate_id, original_id, _) = event
      case duplicate_id == ticket_id, original_id == ticket_id {
        True, False -> DuplicateOf(original_id)
        False, True -> DuplicatedBy(duplicate_id)
        _, _ -> panic as "impossible"
      }
    }),
  )
}
