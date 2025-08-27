import gleam/option.{type Option, None, Some}
import gleam/string
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type CloseTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts
import gleavent_sourced/validation.{require, validate}

// Context built from facts to validate ticket closing business rules
// Contains validation state for the ticket being closed
pub type TicketCloseContext {
  TicketCloseContext(
    exists: Bool,
    is_closed: Bool,
    current_assignee: Option(String),
    priority: Option(String),
  )
}

// Default context state before loading events - assumes ticket doesn't exist
fn initial_context() {
  TicketCloseContext(
    exists: False,
    is_closed: False,
    current_assignee: None,
    priority: None,
  )
}

// Define facts needed to validate ticket closing
fn facts(ticket_id: String) {
  [
    ticket_facts.exists(ticket_id, fn(ctx, exists) {
      TicketCloseContext(..ctx, exists:)
    }),
    ticket_facts.current_assignee(ticket_id, fn(ctx, current_assignee) {
      TicketCloseContext(..ctx, current_assignee:)
    }),
    ticket_facts.is_closed(ticket_id, fn(ctx, is_closed) {
      TicketCloseContext(..ctx, is_closed:)
    }),
    ticket_facts.priority(ticket_id, fn(ctx, priority) {
      TicketCloseContext(..ctx, priority:)
    }),
  ]
}

// Creates command handler with facts to validate ticket before closing
// Uses tagged event isolation to efficiently load ticket state
pub fn create_close_ticket_handler(
  command: CloseTicketCommand,
) -> CommandHandler(
  CloseTicketCommand,
  ticket_events.TicketEvent,
  TicketCloseContext,
  TicketError,
) {
  ticket_commands.make_handler(
    facts(command.ticket_id),
    initial_context(),
    execute,
  )
}

// Core business logic - validates rules then creates TicketClosed event
fn execute(
  command: CloseTicketCommand,
  context: TicketCloseContext,
) -> Result(List(ticket_events.TicketEvent), TicketError) {
  use _ <- validate(ticket_exists, context)
  use _ <- validate(ticket_not_already_closed, context)
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

// Validates the closed_at timestamp is not empty
fn closed_at(closed_at: String) -> Result(Nil, TicketError) {
  require(closed_at != "", BusinessRuleViolation("Closed at cannot be empty"))
}
