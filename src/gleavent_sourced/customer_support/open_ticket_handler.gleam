import gleam/result
import gleam/string

import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type OpenTicketCommand, type TicketError, ValidationError,
}
import gleavent_sourced/customer_support/ticket_events.{
  type TicketEvent, TicketOpened,
}
import gleavent_sourced/validation.{require, validate}

// Creates command handler for opening tickets - no facts needed since this creates new tickets
// Uses empty facts list since no existing state needs to be loaded
pub fn create_open_ticket_handler() -> CommandHandler(
  OpenTicketCommand,
  TicketEvent,
  Nil,
  TicketError,
) {
  command_handler.new(
    Nil,
    // No context needed for ticket creation
    [],
    // No facts needed - creating new tickets
    execute,
    ticket_events.decode,
    ticket_events.encode,
  )
}

// Core business logic - validates input then creates TicketOpened event
fn execute(
  command: OpenTicketCommand,
  _ctx: Nil,
) -> Result(List(TicketEvent), TicketError) {
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

// Validates ticket ID is not empty
fn ticket_id_valid(ticket_id: String) -> Result(Nil, TicketError) {
  require(ticket_id != "", ValidationError("Ticket ID cannot be empty"))
}

// Validates title is not empty and within length limits
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

// Validates priority is one of the allowed values
fn priority_valid(priority: String) -> Result(Nil, TicketError) {
  case priority {
    "low" | "medium" | "high" | "critical" -> Ok(Nil)
    _ ->
      Error(ValidationError(
        "Priority must be one of: low, medium, high, critical",
      ))
  }
}
