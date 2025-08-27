import gleam/result

import gleam/option.{type Option, None, Some}
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type AssignTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts

// Create the CommandHandler for AssignTicket
pub fn create_assign_ticket_handler(
  command: AssignTicketCommand,
) -> CommandHandler(
  AssignTicketCommand,
  ticket_events.TicketEvent,
  TicketAssignmentContext,
  TicketError,
) {
  let facts = facts(command)

  let initial_context =
    Ctx(exists: False, current_assignee: None, is_closed: False)
  ticket_commands.make_handler(facts, initial_context, execute)
}

// Context for tracking ticket assignment state
pub type TicketAssignmentContext {
  Ctx(exists: Bool, current_assignee: Option(String), is_closed: Bool)
}

fn facts(command: AssignTicketCommand) {
  [
    ticket_facts.exists(command.ticket_id, fn(c, exists) { Ctx(..c, exists:) }),
    ticket_facts.current_assignee(command.ticket_id, fn(c, current_assignee) {
      Ctx(..c, current_assignee:)
    }),
    ticket_facts.is_closed(command.ticket_id, fn(c, is_closed) {
      Ctx(..c, is_closed:)
    }),
  ]
}

fn execute(command: AssignTicketCommand, context) {
  use _ <- result.try(validate_ticket_exists(context))
  use _ <- result.try(validate_ticket_not_closed(context))
  use _ <- result.try(validate_not_already_assigned(context, command.assignee))
  use _ <- result.try(validate_assignee(command.assignee))
  use _ <- result.try(validate_assigned_at(command.assigned_at))
  Ok([
    ticket_events.TicketAssigned(
      command.ticket_id,
      command.assignee,
      command.assigned_at,
    ),
  ])
}

fn validate_ticket_exists(
  context: TicketAssignmentContext,
) -> Result(Nil, TicketError) {
  case context.exists {
    True -> Ok(Nil)
    False -> Error(BusinessRuleViolation("Ticket does not exist"))
  }
}

fn validate_ticket_not_closed(
  context: TicketAssignmentContext,
) -> Result(Nil, TicketError) {
  case context.is_closed {
    False -> Ok(Nil)
    True -> Error(BusinessRuleViolation("Cannot assign closed ticket"))
  }
}

fn validate_not_already_assigned(
  context: TicketAssignmentContext,
  new_assignee: String,
) -> Result(Nil, TicketError) {
  case context.current_assignee {
    None -> Ok(Nil)
    Some(existing_assignee) ->
      case existing_assignee == new_assignee {
        True ->
          Error(BusinessRuleViolation(
            "Ticket already assigned to " <> existing_assignee,
          ))
        False ->
          Error(BusinessRuleViolation(
            "Ticket already assigned to " <> existing_assignee,
          ))
      }
  }
}

fn validate_assignee(assignee: String) -> Result(Nil, TicketError) {
  case assignee {
    "" -> Error(BusinessRuleViolation("Assignee cannot be empty"))
    _ -> Ok(Nil)
  }
}

fn validate_assigned_at(assigned_at: String) -> Result(Nil, TicketError) {
  case assigned_at {
    "" -> Error(BusinessRuleViolation("Assigned at cannot be empty"))
    _ -> Ok(Nil)
  }
}
