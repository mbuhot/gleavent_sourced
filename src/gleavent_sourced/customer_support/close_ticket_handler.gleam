import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type CloseTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/event_filter

// Context for tracking ticket state for closing
pub type TicketCloseContext {
  TicketCloseContext(
    exists: Bool,
    is_closed: Bool,
    current_assignee: Option(String),
    priority: Option(String),
  )
}

// Create the CommandHandler for CloseTicket
pub fn create_close_ticket_handler() -> CommandHandler(
  CloseTicketCommand,
  ticket_events.TicketEvent,
  TicketCloseContext,
  TicketError,
) {
  command_handler.CommandHandler(
    event_filter: event_filter,
    context_reducer: reducer,
    initial_context: initial_context(),
    command_logic: execute,
    event_mapper: ticket_events.ticket_event_mapper,
    event_converter: ticket_events.ticket_event_to_type_and_payload,
    metadata_generator: metadata,
  )
}

fn initial_context() -> TicketCloseContext {
  TicketCloseContext(
    exists: False,
    is_closed: False,
    current_assignee: None,
    priority: None,
  )
}

fn event_filter(command: CloseTicketCommand) -> event_filter.EventFilter {
  let id_filter = event_filter.attr_string("ticket_id", command.ticket_id)
  event_filter.new()
  |> event_filter.for_type("TicketOpened", [id_filter])
  |> event_filter.for_type("TicketAssigned", [id_filter])
  |> event_filter.for_type("TicketClosed", [id_filter])
}

fn reducer(
  events: List(ticket_events.TicketEvent),
  initial: TicketCloseContext,
) -> TicketCloseContext {
  // Fold events to build current ticket state
  list.fold(events, initial, fn(context, event) {
    case event {
      ticket_events.TicketOpened(_, _, _, priority) ->
        TicketCloseContext(..context, exists: True, priority: Some(priority))
      ticket_events.TicketAssigned(_, assignee, _) ->
        TicketCloseContext(..context, current_assignee: Some(assignee))
      ticket_events.TicketClosed(..) ->
        TicketCloseContext(..context, is_closed: True)
    }
  })
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

fn metadata(
  command: CloseTicketCommand,
  _context: TicketCloseContext,
) -> dict.Dict(String, String) {
  dict.from_list([
    #("command_type", "CloseTicket"),
    #("ticket_id", command.ticket_id),
    #("closed_by", command.closed_by),
    #("source", "ticket_service"),
    #("version", "1"),
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
