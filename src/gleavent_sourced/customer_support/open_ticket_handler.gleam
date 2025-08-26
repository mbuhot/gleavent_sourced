import gleam/dict
import gleam/result
import gleam/string
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type OpenTicketCommand, type TicketError, OpenTicketCommand, ValidationError,
}
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/event_filter

// Create the CommandHandler for OpenTicket
pub fn create_open_ticket_handler() -> CommandHandler(
  OpenTicketCommand,
  ticket_events.TicketEvent,
  Nil,
  TicketError,
) {
  command_handler.CommandHandler(
    event_filter: fn(_command) {
      // New tickets don't need to load existing events
      event_filter.new()
    },
    context_reducer: fn(_events, _initial) {
      // No context needed for new tickets
      Nil
    },
    initial_context: Nil,
    command_logic: fn(command, _context) {
      case command {
        OpenTicketCommand(ticket_id, title, description, priority) -> {
          validate_open_ticket_command(ticket_id, title, description, priority)
        }
      }
    },
    event_mapper: ticket_events.ticket_event_mapper,
    event_converter: ticket_events.ticket_event_to_type_and_payload,
    metadata_generator: fn(command, _context) {
      case command {
        OpenTicketCommand(ticket_id, _, _, _) ->
          dict.from_list([
            #("command_type", "OpenTicket"),
            #("ticket_id", ticket_id),
            #("source", "ticket_service"),
            #("version", "1"),
          ])
      }
    },
  )
}

// Validation logic for OpenTicket command
fn validate_open_ticket_command(
  ticket_id: String,
  title: String,
  description: String,
  priority: String,
) -> Result(List(ticket_events.TicketEvent), TicketError) {
  use _ <- result.try(validate_ticket_id(ticket_id))
  use _ <- result.try(validate_title(title))
  use _ <- result.try(validate_priority(priority))
  Ok([ticket_events.TicketOpened(ticket_id, title, description, priority)])
}

fn validate_ticket_id(ticket_id: String) -> Result(Nil, TicketError) {
  case ticket_id {
    "" -> Error(ValidationError("Ticket ID cannot be empty"))
    _ -> Ok(Nil)
  }
}

fn validate_title(title: String) -> Result(Nil, TicketError) {
  case title {
    "" -> Error(ValidationError("Title cannot be empty"))
    _ ->
      case string.length(title) > 100 {
        True -> Error(ValidationError("Title cannot exceed 100 characters"))
        False -> Ok(Nil)
      }
  }
}

fn validate_priority(priority: String) -> Result(Nil, TicketError) {
  case priority {
    "low" | "medium" | "high" | "critical" -> Ok(Nil)
    _ ->
      Error(ValidationError(
        "Priority must be one of: low, medium, high, critical",
      ))
  }
}
