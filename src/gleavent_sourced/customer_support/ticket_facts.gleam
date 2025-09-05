import gleam/list
import gleam/option.{type Option, None, Some}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/facts
import gleavent_sourced/parrot_pog
import gleavent_sourced/sql
import pog

fn query_by_type_and_id(event_type, ticket_id, apply_events) {
  facts.new_fact(
    sql: "SELECT * "
      <> "FROM events e "
      <> "WHERE e.event_type = $1::text AND "
      <> "  e.payload @> jsonb_build_object('ticket_id', $2::text)",
    params: [pog.text(event_type), pog.text(ticket_id)],
    apply_events: apply_events,
  )
}

fn fold_into(
  update_context: fn(context, value) -> context,
  zero: value,
  apply: fn(value, event) -> value,
) {
  fn(context, events) {
    list.fold(events, zero, apply) |> update_context(context, _)
  }
}

/// Whether a ticket exists (derived from TicketOpened events)
pub fn exists(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(context, TicketEvent) {
  query_by_type_and_id(
    "TicketOpened",
    ticket_id,
    fold_into(update_context, False, fn(_acc, _event) { True }),
  )
}

/// Whether a ticket is closed (derived from TicketClosed events)
pub fn is_closed(
  ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(context, TicketEvent) {
  query_by_type_and_id(
    "TicketClosed",
    ticket_id,
    fold_into(update_context, False, fn(_acc, _event) { True }),
  )
}

/// Current assignee of a ticket (derived from TicketAssigned events)
pub fn current_assignee(
  ticket_id: String,
  update_context: fn(context, Option(String)) -> context,
) -> facts.Fact(context, TicketEvent) {
  query_by_type_and_id(
    "TicketAssigned",
    ticket_id,
    fold_into(update_context, None, fn(acc, event) {
      case event {
        ticket_events.TicketAssigned(_, assignee, _) -> Some(assignee)
        _ -> acc
      }
    }),
  )
}

/// Priority of a ticket (derived from TicketOpened events)
pub fn priority(
  ticket_id: String,
  update_context: fn(context, Option(String)) -> context,
) -> facts.Fact(context, TicketEvent) {
  query_by_type_and_id(
    "TicketOpened",
    ticket_id,
    fold_into(update_context, None, fn(acc, event) {
      case event {
        ticket_events.TicketOpened(_, _, _, priority) -> Some(priority)
        _ -> acc
      }
    }),
  )
}

/// List of child ticket IDs linked to a parent ticket
pub fn child_tickets(
  parent_ticket_id: String,
  update_context: fn(context, List(String)) -> context,
) -> facts.Fact(context, TicketEvent) {
  let update_with_reverse = fn(context, children) {
    update_context(context, list.reverse(children))
  }
  // Get the SQL query from generated sql.gleam
  let #(sql_query, params, _decoder) = sql.child_tickets(parent_ticket_id)

  // Convert parrot params to pog params
  let pog_params = list.map(params, parrot_pog.parrot_to_pog)

  facts.new_fact(
    sql: sql_query,
    params: pog_params,
    apply_events: fold_into(update_with_reverse, [], fn(acc, event) {
      case event {
        ticket_events.TicketParentLinked(child_id, parent_id) ->
          case parent_id == parent_ticket_id {
            True -> [child_id, ..acc]
            False -> acc
          }
        _ -> acc
      }
    }),
  )
}

/// Duplicate status of a ticket (derived from TicketMarkedDuplicate events)
pub type DuplicateStatus {
  Unique
  DuplicateOf(original_ticket_id: String)
  DuplicatedBy(duplicate_ticket_id: String)
}

pub fn duplicate_status(
  ticket_id: String,
  update_context: fn(context, DuplicateStatus) -> context,
) -> facts.Fact(context, TicketEvent) {
  // Get the SQL query from generated sql.gleam
  let #(sql_query, params, _decoder) = sql.duplicate_status(ticket_id)

  // Convert parrot params to pog params
  let pog_params = list.map(params, parrot_pog.parrot_to_pog)

  facts.new_fact(
    sql: sql_query,
    params: pog_params,
    apply_events: fn(context, events) {
      let status = case events {
        [] -> Unique
        [ticket_events.TicketMarkedDuplicate(duplicate_id, original_id, _), ..] ->
          case duplicate_id == ticket_id, original_id == ticket_id {
            True, False -> DuplicateOf(original_id)
            False, True -> DuplicatedBy(duplicate_id)
            _, _ -> Unique
          }
        _ -> Unique
      }
      update_context(context, status)
    },
  )
}

/// Whether all child tickets of a parent are closed
pub fn all_child_tickets_closed(
  parent_ticket_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(context, TicketEvent) {
  // Get the optimized SQL query from generated sql.gleam
  let #(sql_query, params, _decoder) =
    sql.all_child_tickets_closed(parent_ticket_id)

  // Convert parrot params to pog params
  let pog_params = list.map(params, parrot_pog.parrot_to_pog)

  facts.new_fact(
    sql: sql_query,
    params: pog_params,
    apply_events: fn(context, events) {
      let child_ids =
        list.filter_map(events, fn(event) {
          case event {
            ticket_events.TicketParentLinked(child_id, parent_id) ->
              case parent_id == parent_ticket_id {
                True -> Ok(child_id)
                False -> Error(Nil)
              }
            _ -> Error(Nil)
          }
        })

      let closed_ids =
        list.filter_map(events, fn(event) {
          case event {
            ticket_events.TicketClosed(ticket_id, _, _) -> Ok(ticket_id)
            _ -> Error(Nil)
          }
        })

      let all_closed = case child_ids {
        [] -> True
        // No children means all are closed
        _ ->
          list.all(child_ids, fn(child_id) {
            list.contains(closed_ids, child_id)
          })
      }

      update_context(context, all_closed)
    },
  )
}
