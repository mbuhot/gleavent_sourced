import gleam/dict
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts
import gleavent_sourced/command_handler

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

// Error types for ticket operations
pub type TicketError {
  ValidationError(message: String)
  BusinessRuleViolation(message: String)
}

pub fn make_handler(facts, initial_context, execute) {
  command_handler.CommandHandler(
    event_filter: ticket_facts.event_filter(facts),
    initial_context: initial_context,
    context_reducer: ticket_facts.build_context(facts),
    command_logic: execute,
    event_mapper: ticket_events.ticket_event_mapper,
    event_converter: ticket_events.ticket_event_to_type_and_payload,
    metadata_generator: metadata)
}

fn metadata(_command, _context) {
  dict.from_list([
    #("source", "ticket_service"),
    #("version", "1"),
  ])
}
