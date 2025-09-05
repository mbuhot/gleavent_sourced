import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type CloseTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/facts
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
fn initial_context(ticket_id: String) {
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

// Custom optimized fact using the sophisticated SQL from sql.gleam
// This single query efficiently loads all parent and child ticket events
fn ticket_close_fact(
  ticket_id: String,
) -> facts.Fact(TicketCloseContext, TicketEvent) {
  // Get the optimized SQL query that loads parent + child events in one query
  let #(sql_query, params, _decoder) = sql.ticket_closed_events(ticket_id)

  // Convert parrot params to pog params
  let pog_params = list.map(params, parrot_pog.parrot_to_pog)

  facts.new_fact(
    sql: sql_query,
    params: pog_params,
    apply_events: fn(context, events) {
      // Custom reducer that builds complete context from all events
      list.fold(events, context, process_event_for_context)
    },
  )
}

// Process each event to build the comprehensive context
// Handles parent ticket state + child ticket tracking
fn process_event_for_context(
  context: TicketCloseContext,
  event: TicketEvent,
) -> TicketCloseContext {
  case event {
    // Parent ticket opened - establishes existence and priority
    ticket_events.TicketOpened(ticket_id: id, priority: p, ..)
      if id == context.ticket_id
    -> TicketCloseContext(..context, exists: True, priority: Some(p))

    // Child ticket opened - track as open child
    ticket_events.TicketOpened(ticket_id: id, ..) ->
      TicketCloseContext(..context, open_children: [id, ..context.open_children])

    // Parent ticket assigned - track current assignee
    ticket_events.TicketAssigned(ticket_id: id, assignee: a, ..)
      if id == context.ticket_id
    -> TicketCloseContext(..context, current_assignee: Some(a))

    ticket_events.TicketAssigned(..) -> context

    // Parent ticket closed - mark as closed
    ticket_events.TicketClosed(ticket_id: id, ..) if id == context.ticket_id ->
      TicketCloseContext(..context, is_closed: True)

    // Child ticket closed - remove from open children
    ticket_events.TicketClosed(ticket_id: id, ..) ->
      TicketCloseContext(
        ..context,
        open_children: list.filter(context.open_children, fn(child_id) {
          child_id != id
        }),
      )

    // Child linked to parent - track linked children
    ticket_events.TicketParentLinked(
      ticket_id: child_id,
      parent_ticket_id: parent_id,
    )
      if parent_id == context.ticket_id
    ->
      TicketCloseContext(..context, linked_children: [
        child_id,
        ..context.linked_children
      ])

    _ -> context
  }
}

// Creates command handler with custom optimized SQL fact
// Single query loads all necessary parent + child ticket data
pub fn create_close_ticket_handler(
  command: CloseTicketCommand,
) -> CommandHandler(
  CloseTicketCommand,
  TicketEvent,
  TicketCloseContext,
  TicketError,
) {
  command_handler.new(
    initial_context(command.ticket_id),
    [ticket_close_fact(command.ticket_id)],
    execute,
    ticket_events.decode,
    ticket_events.encode,
  )
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
    ticket_events.TicketClosed(
      command.ticket_id,
      command.resolution,
      command.closed_at,
    ),
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
