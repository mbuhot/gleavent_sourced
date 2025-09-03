import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type CloseTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events.{
  type TicketEvent, TicketAssigned, TicketClosed, TicketOpened,
}
import gleavent_sourced/event_filter
import gleavent_sourced/parrot_pog
import gleavent_sourced/sql
import gleavent_sourced/validation.{require, validate}

// Context built from facts to validate ticket closing business rules
// Contains validation state for the ticket being closed
pub type TicketCloseContext {
  TicketCloseContext(
    ticket_id: String,
    exists: Bool,
    is_closed: Bool,
    current_assignee: Option(String),
    priority: Option(String),
    linked_children: List(String),
    open_children: List(String),
  )
}

// Default context state before loading events - assumes ticket doesn't exist
fn initial_context(ticket_id) {
  TicketCloseContext(
    ticket_id: ticket_id,
    exists: False,
    is_closed: False,
    current_assignee: None,
    priority: None,
    linked_children: [],
    open_children: [],
  )
}

// Create custom SQL filter for ticket closed events
pub fn ticket_closed_events_filter(
  ticket_id: String,
  fact_id: String,
) -> event_filter.EventFilter {
  let #(sql, params, _decoder) =
    sql.ticket_closed_events(ticket_id: ticket_id, fact_id: fact_id)
  let pog_params = list.map(params, parrot_pog.parrot_to_pog)
  event_filter.custom_sql(sql, pog_params)
}

// Creates command handler with facts to validate ticket before closing
// Uses tagged event isolation to efficiently load ticket state
pub fn create_close_ticket_handler(
  command: CloseTicketCommand,
) -> CommandHandler(
  CloseTicketCommand,
  TicketEvent,
  TicketCloseContext,
  TicketError,
) {
  initial_context(command.ticket_id)
  |> ticket_commands.handler(execute)
  |> ticket_commands.with_event_filter(ticket_closed_events_filter(
    command.ticket_id,
    "closed",
  ))
  |> ticket_commands.with_reducer(context_reducer)
}

fn context_reducer(events_dict, ctx: TicketCloseContext) {
  dict.values(events_dict)
  |> list.flatten()
  |> list.fold(ctx, fn(ctx, e: TicketEvent) {
    case e {
      TicketOpened(ticket_id: id, priority: p, ..) if id == ctx.ticket_id ->
        TicketCloseContext(..ctx, exists: True, priority: Some(p))

      TicketOpened(ticket_id: id, ..) ->
        TicketCloseContext(..ctx, open_children: [id, ..ctx.open_children])

      TicketAssigned(ticket_id: id, assignee: a, ..) if id == ctx.ticket_id ->
        TicketCloseContext(..ctx, current_assignee: Some(a))
      TicketAssigned(..) -> ctx

      TicketClosed(ticket_id: id, ..) if id == ctx.ticket_id ->
        TicketCloseContext(..ctx, is_closed: True)
      TicketClosed(ticket_id: id, ..) ->
        TicketCloseContext(
          ..ctx,
          open_children: list.filter(ctx.open_children, fn(x) { x != id }),
        )
      _ -> ctx
    }
  })
}

// Core business logic - validates rules then creates TicketClosed event
fn execute(
  command: CloseTicketCommand,
  context: TicketCloseContext,
) -> Result(List(TicketEvent), TicketError) {
  use _ <- validate(ticket_exists, context)
  use _ <- validate(ticket_not_already_closed, context)
  use _ <- validate(no_open_children, context)
  use _ <- validate(closer_permissions(_, command.closed_by), context)
  use _ <- validate(resolution_detail(_, command.resolution), context)
  use _ <- validate(closed_at, command.closed_at)
  Ok([
    TicketClosed(command.ticket_id, command.resolution, command.closed_at),
  ])
}

// Validates the ticket exists before allowing closure
fn ticket_exists(context: TicketCloseContext) -> Result(Nil, TicketError) {
  require(context.exists, BusinessRuleViolation("Ticket does not exist"))
}

// Validates the ticket is not already closed
fn ticket_not_already_closed(
  context: TicketCloseContext,
) -> Result(Nil, TicketError) {
  require(!context.is_closed, BusinessRuleViolation("Ticket is already closed"))
}

// Validates only the assignee can close the ticket
fn closer_permissions(
  context: TicketCloseContext,
  closed_by: String,
) -> Result(Nil, TicketError) {
  case context.current_assignee {
    None ->
      Error(BusinessRuleViolation(
        "Ticket must be assigned before it can be closed",
      ))
    Some(assignee) ->
      case assignee == closed_by {
        True -> Ok(Nil)
        False ->
          Error(BusinessRuleViolation(
            "Only the assignee (" <> assignee <> ") can close this ticket",
          ))
      }
  }
}

// Validates resolution meets requirements based on ticket priority
fn resolution_detail(
  context: TicketCloseContext,
  resolution: String,
) -> Result(Nil, TicketError) {
  case context.priority {
    Some("high") | Some("critical") -> {
      case string.length(resolution) >= 20 {
        True -> Ok(Nil)
        False ->
          Error(BusinessRuleViolation(
            "High priority tickets require detailed resolution (minimum 20 characters)",
          ))
      }
    }
    _ -> {
      case resolution {
        "" -> Error(BusinessRuleViolation("Resolution cannot be empty"))
        _ -> Ok(Nil)
      }
    }
  }
}

// Validates the ticket has no open child tickets
fn no_open_children(context: TicketCloseContext) -> Result(Nil, TicketError) {
  require(
    context.open_children == [],
    BusinessRuleViolation("Cannot close parent ticket with open child tickets"),
  )
}

// Validates the closed_at timestamp is not empty
fn closed_at(closed_at: String) -> Result(Nil, TicketError) {
  require(closed_at != "", BusinessRuleViolation("Closed at cannot be empty"))
}
