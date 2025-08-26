import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type AssignTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/event_filter

// Context for tracking ticket assignment state
pub type TicketAssignmentContext {
  TicketAssignmentContext(
    exists: Bool,
    current_assignee: Option(String),
    is_closed: Bool,
  )
}

// Create the CommandHandler for AssignTicket
pub fn create_assign_ticket_handler() -> CommandHandler(
  AssignTicketCommand,
  ticket_events.TicketEvent,
  TicketAssignmentContext,
  TicketError,
) {
  command_handler.CommandHandler(
    event_filter: event_filter,
    context_reducer: reducer,
    initial_context: initial_context(),
    command_logic: execute,
    event_mapper: ticket_events.ticket_event_mapper,
    event_converter: ticket_events.ticket_event_to_type_and_payload,
    metadata_generator: metadata)
}

fn event_filter(command: AssignTicketCommand) -> event_filter.EventFilter {
  let id_filter = event_filter.attr_string("ticket_id", command.ticket_id)
  event_filter.new()
  |> event_filter.for_type("TicketOpened", [id_filter])
  |> event_filter.for_type("TicketAssigned", [id_filter])
  |> event_filter.for_type("TicketClosed", [id_filter])
}

fn reducer(events, initial) {
  list.fold(events, initial, fn(context, event) {
    case event {
      ticket_events.TicketOpened(..) ->
        TicketAssignmentContext(..context, exists: True)
      ticket_events.TicketAssigned(_, assignee, _) ->
        TicketAssignmentContext(..context, current_assignee: Some(assignee))
      ticket_events.TicketClosed(..) ->
        TicketAssignmentContext(..context, is_closed: True)
    }
  })
}

fn initial_context() -> TicketAssignmentContext {
  TicketAssignmentContext(
    exists: False,
    current_assignee: None,
    is_closed: False,
  )
}

fn execute(command: AssignTicketCommand, context) {
  use _ <- result.try(validate_ticket_exists(context))
  use _ <- result.try(validate_ticket_not_closed(context))
  use _ <- result.try(validate_not_already_assigned(context, command.assignee))
  use _ <- result.try(validate_assignee(command.assignee))
  use _ <- result.try(validate_assigned_at(command.assigned_at))
  Ok([ticket_events.TicketAssigned(command.ticket_id, command.assignee, command.assigned_at)])
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

fn metadata(_command, _context) {
  dict.from_list([
    #("source", "ticket_service"),
    #("version", "1"),
  ])
}
