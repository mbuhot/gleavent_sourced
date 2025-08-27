import gleam/dict
import gleavent_sourced/command_handler
import gleavent_sourced/customer_support/ticket_events

import gleavent_sourced/facts

// Command types for ticket operations

pub type OpenTicketCommand {
  OpenTicketCommand(
    ticket_id: String,
    title: String,
    description: String,
    priority: String,
  )
}

pub type AssignTicketCommand {
  AssignTicketCommand(ticket_id: String, assignee: String, assigned_at: String)
}

pub type CloseTicketCommand {
  CloseTicketCommand(
    ticket_id: String,
    resolution: String,
    closed_at: String,
    closed_by: String,
  )
}

pub type MarkDuplicateCommand {
  MarkDuplicateCommand(
    duplicate_ticket_id: String,
    original_ticket_id: String,
    marked_at: String,
  )
}

// Error types for ticket operations
pub type TicketError {
  ValidationError(message: String)
  BusinessRuleViolation(message: String)
}

pub fn make_handler(facts, initial_context, execute) {
  command_handler.CommandHandler(
    event_filter: facts.event_filter(facts),
    initial_context: initial_context,
    context_reducer: facts.build_context(facts),
    command_logic: execute,
    event_mapper: ticket_events.decode,
    event_converter: ticket_events.encode,
    metadata_generator: metadata,
  )
}

fn metadata(_command, _context) {
  dict.from_list([
    #("source", "ticket_service"),
    #("version", "1"),
  ])
}
