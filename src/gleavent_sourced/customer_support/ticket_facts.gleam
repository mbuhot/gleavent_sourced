import gleam/option.{type Option, None, Some}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
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

fn for_duplicate_relationships(ticket_id) {
  // Find TicketMarkedDuplicate events where this ticket is either the original or the duplicate
  event_filter.new()
  |> event_filter.for_type("TicketMarkedDuplicate", [
    event_filter.attr_string("duplicate_ticket_id", ticket_id),
  ])
  |> event_filter.for_type("TicketMarkedDuplicate", [
    event_filter.attr_string("original_ticket_id", ticket_id),
  ])
}

// Fact: Whether a ticket exists (derived from TicketOpened)
pub fn exists(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.new_fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    apply_events: facts.fold_into(update_context, False, fn(acc, event) {
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
  facts.new_fact(
    event_filter: for_type_with_id("TicketClosed", ticket_id),
    apply_events: facts.fold_into(update_context, False, fn(acc, event) {
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
  facts.new_fact(
    event_filter: for_type_with_id("TicketAssigned", ticket_id),
    apply_events: facts.fold_into(update_context, None, fn(acc, event) {
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
  facts.new_fact(
    event_filter: for_type_with_id("TicketOpened", ticket_id),
    apply_events: facts.fold_into(update_context, None, fn(acc, event) {
      case event {
        ticket_events.TicketOpened(_, _, _, priority) -> Some(priority)
        _ -> acc
      }
    }),
  )
}

// Fact: Duplicate status of ticket (derived from TicketMarkedDuplicate)
// Returns status indicating if ticket is unique, duplicate of another, or has duplicates
pub fn duplicate_status(
  ticket_id: String,
  update_context: fn(context, DuplicateStatus) -> context,
) -> facts.Fact(TicketEvent, context) {
  facts.new_fact(
    event_filter: for_duplicate_relationships(ticket_id),
    apply_events: facts.fold_into(update_context, Unique, fn(acc, event) {
      case event {
        ticket_events.TicketMarkedDuplicate(duplicate_id, original_id, _) -> {
          case duplicate_id == ticket_id, original_id == ticket_id {
            True, False -> DuplicateOf(original_id)
            // This ticket is marked as duplicate
            False, True -> DuplicatedBy(duplicate_id)
            // This ticket has a duplicate
            _, _ -> acc
            // Shouldn't happen with proper filter, but keep existing status
          }
        }
        _ -> acc
      }
    }),
  )
}
