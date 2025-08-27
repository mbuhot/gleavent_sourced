import gleam/dict
import gleam/result
import gleam/string
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type OpenTicketCommand, type TicketError, ValidationError,
}
import gleavent_sourced/customer_support/ticket_events.{TicketOpened}
import gleavent_sourced/event_filter
import gleavent_sourced/validation.{require, validate}

// Create the CommandHandler for OpenTicket
pub fn create_open_ticket_handler() -> CommandHandler(
  OpenTicketCommand,
  ticket_events.TicketEvent,
  Nil,
  TicketError,
) {
  command_handler.CommandHandler(
    event_filter: event_filter.new(),
    context_reducer: fn(_events_by_fact, _initial) {
      // No context needed for new tickets
      Nil
    },
    initial_context: Nil,
    command_logic: execute,
    event_mapper: ticket_events.decode,
    event_converter: ticket_events.encode,
    metadata_generator: fn(command: OpenTicketCommand, _context) {
      dict.from_list([
        #("command_type", "OpenTicket"),
        #("ticket_id", command.ticket_id),
        #("source", "ticket_service"),
        #("version", "1"),
      ])
    },
  )
}

fn execute(
  command: OpenTicketCommand,
  _ctx: Nil,
) -> Result(List(ticket_events.TicketEvent), TicketError) {
  use _ <- validate(ticket_id_valid, command.ticket_id)
  use _ <- validate(title_valid, command.title)
  use _ <- validate(priority_valid, command.priority)
  Ok([
    TicketOpened(
      command.ticket_id,
      command.title,
      command.description,
      command.priority,
    ),
  ])
}

fn ticket_id_valid(ticket_id: String) -> Result(Nil, TicketError) {
  require(ticket_id != "", ValidationError("Ticket ID cannot be empty"))
}

fn title_valid(title: String) -> Result(Nil, TicketError) {
  use _ <- result.try(require(
    title != "",
    ValidationError("Title cannot be empty"),
  ))
  require(
    string.length(title) <= 100,
    ValidationError("Title cannot exceed 100 characters"),
  )
}

fn priority_valid(priority: String) -> Result(Nil, TicketError) {
  case priority {
    "low" | "medium" | "high" | "critical" -> Ok(Nil)
    _ ->
      Error(ValidationError(
        "Priority must be one of: low, medium, high, critical",
      ))
  }
}
