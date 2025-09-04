import gleam/option.{type Option, None, Some}

import gleavent_sourced/command_handler_v2.{type CommandHandlerV2}
import gleavent_sourced/customer_support/ticket_commands.{
  type AssignTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/customer_support/ticket_facts_v2
import gleavent_sourced/validation.{require, validate}

// Context built from facts to validate ticket assignment business rules
// Contains validation state for the ticket being assigned
pub type TicketAssignmentContext {
  TicketAssignmentContext(
    exists: Bool,
    current_assignee: Option(String),
    is_closed: Bool,
  )
}

// Default context state before loading events - assumes ticket doesn't exist
fn initial_context() {
  TicketAssignmentContext(
    exists: False,
    current_assignee: None,
    is_closed: False,
  )
}

// Define facts needed to validate ticket assignment
fn facts(ticket_id: String) {
  [
    ticket_facts_v2.exists(ticket_id, fn(ctx, exists) {
      TicketAssignmentContext(..ctx, exists:)
    }),
    ticket_facts_v2.current_assignee(ticket_id, fn(ctx, current_assignee) {
      TicketAssignmentContext(..ctx, current_assignee:)
    }),
    ticket_facts_v2.is_closed(ticket_id, fn(ctx, is_closed) {
      TicketAssignmentContext(..ctx, is_closed:)
    }),
  ]
}

// Creates command handler with facts to validate ticket before assignment
// Uses strongly-typed facts system for efficient event querying
pub fn create_assign_ticket_handler_v2(
  command: AssignTicketCommand,
) -> CommandHandlerV2(
  AssignTicketCommand,
  TicketEvent,
  TicketAssignmentContext,
  TicketError,
) {
  command_handler_v2.new(
    initial_context(),
    facts(command.ticket_id),
    execute,
    ticket_events.decode,
    ticket_events.encode,
  )
}

// Core business logic - validates rules then creates TicketAssigned event
fn execute(
  command: AssignTicketCommand,
  context: TicketAssignmentContext,
) -> Result(List(TicketEvent), TicketError) {
  use _ <- validate(ticket_exists, context)
  use _ <- validate(ticket_not_closed, context)
  use _ <- validate(not_already_assigned, context)
  use _ <- validate(assignee, command.assignee)
  use _ <- validate(assigned_at, command.assigned_at)
  Ok([
    ticket_events.TicketAssigned(
      command.ticket_id,
      command.assignee,
      command.assigned_at,
    ),
  ])
}

// Validates the ticket exists before allowing assignment
fn ticket_exists(context: TicketAssignmentContext) -> Result(Nil, TicketError) {
  require(context.exists, BusinessRuleViolation("Ticket does not exist"))
}

// Validates the ticket is not closed before allowing assignment
fn ticket_not_closed(
  context: TicketAssignmentContext,
) -> Result(Nil, TicketError) {
  require(
    !context.is_closed,
    BusinessRuleViolation("Cannot assign closed ticket"),
  )
}

// Prevents assigning a ticket that already has an assignee
fn not_already_assigned(
  context: TicketAssignmentContext,
) -> Result(Nil, TicketError) {
  case context.current_assignee {
    None -> Ok(Nil)
    Some(existing_assignee) ->
      Error(BusinessRuleViolation(
        "Ticket already assigned to " <> existing_assignee,
      ))
  }
}

// Validates the assignee field is not empty
fn assignee(assignee: String) -> Result(Nil, TicketError) {
  require(assignee != "", BusinessRuleViolation("Assignee cannot be empty"))
}

// Validates the assigned_at timestamp is not empty
fn assigned_at(assigned_at: String) -> Result(Nil, TicketError) {
  require(
    assigned_at != "",
    BusinessRuleViolation("Assigned at cannot be empty"),
  )
}
