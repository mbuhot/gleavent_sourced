import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type CloseTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts

// Create the CommandHandler for CloseTicket
pub fn create_close_ticket_handler(
  command: CloseTicketCommand,
) -> CommandHandler(
  CloseTicketCommand,
  ticket_events.TicketEvent,
  TicketCloseContext,
  TicketError,
) {
  let facts = facts(command)

  let initial_context =
    Ctx(exists: False, is_closed: False, current_assignee: None, priority: None)
  ticket_commands.make_handler(facts, initial_context, execute)
}

// Context for tracking ticket state for closing
pub type TicketCloseContext {
  Ctx(
    exists: Bool,
    is_closed: Bool,
    current_assignee: Option(String),
    priority: Option(String),
  )
}

fn facts(command: CloseTicketCommand) {
  [
    ticket_facts.exists(command.ticket_id, fn(c, exists) { Ctx(..c, exists:) }),
    ticket_facts.current_assignee(command.ticket_id, fn(c, current_assignee) {
      Ctx(..c, current_assignee:)
    }),
    ticket_facts.is_closed(command.ticket_id, fn(c, is_closed) {
      Ctx(..c, is_closed:)
    }),
    ticket_facts.priority(command.ticket_id, fn(c, priority) {
      Ctx(..c, priority:)
    }),
  ]
}

fn execute(
  command: CloseTicketCommand,
  context: TicketCloseContext,
) -> Result(List(ticket_events.TicketEvent), TicketError) {
  use _ <- result.try(validate_ticket_exists(context))
  use _ <- result.try(validate_ticket_not_already_closed(context))
  use _ <- result.try(validate_closer_permissions(context, command.closed_by))
  use _ <- result.try(validate_resolution_detail(context, command.resolution))
  use _ <- result.try(validate_closed_at(command.closed_at))
  Ok([
    ticket_events.TicketClosed(
      command.ticket_id,
      command.resolution,
      command.closed_at,
    ),
  ])
}

fn validate_ticket_exists(
  context: TicketCloseContext,
) -> Result(Nil, TicketError) {
  case context.exists {
    True -> Ok(Nil)
    False -> Error(BusinessRuleViolation("Ticket does not exist"))
  }
}

fn validate_ticket_not_already_closed(
  context: TicketCloseContext,
) -> Result(Nil, TicketError) {
  case context.is_closed {
    False -> Ok(Nil)
    True -> Error(BusinessRuleViolation("Ticket is already closed"))
  }
}

fn validate_closer_permissions(
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

fn validate_resolution_detail(
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

fn validate_closed_at(closed_at: String) -> Result(Nil, TicketError) {
  case closed_at {
    "" -> Error(BusinessRuleViolation("Closed at cannot be empty"))
    _ -> Ok(Nil)
  }
}
