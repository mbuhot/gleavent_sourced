import gleam/dict
import gleam/option.{type Option}
import gleavent_sourced/command_handler.{CommandHandler}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/event_filter
import gleavent_sourced/facts.{type Fact}
import pog

// Command types for ticket operations

pub type OpenTicketCommand {
  OpenTicketCommand(
    ticket_id: String,
    title: String,
    description: String,
    priority: String,
    parent_ticket_id: Option(String),
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

pub type BulkAssignCommand {
  BulkAssignCommand(
    ticket_ids: List(String),
    assignee: String,
    assigned_at: String,
  )
}

// Error types for ticket operations
pub type TicketError {
  ValidationError(message: String)
  BusinessRuleViolation(message: String)
}

pub fn handler(initial_context, execute) {
  CommandHandler(
    event_filter: event_filter.new(),
    initial_context: initial_context,
    context_reducer: fn(_events_dict, context) { context },
    enrich_context: fn(_connection, context) { Ok(context) },
    command_logic: execute,
    event_mapper: ticket_events.decode,
    event_converter: ticket_events.encode,
    metadata_generator: fn(_cmd, _context) { dict.new() },
  )
}

pub fn with_event_filter(
  handler: command_handler.CommandHandler(command, event, context, error),
  event_filter: event_filter.EventFilter,
) -> command_handler.CommandHandler(command, event, context, error) {
  CommandHandler(..handler, event_filter:)
}

pub fn with_reducer(handler, context_reducer) {
  CommandHandler(..handler, context_reducer:)
}

pub fn with_facts(
  handler: command_handler.CommandHandler(a, b, c, d),
  facts: List(Fact(b, c)),
) -> command_handler.CommandHandler(a, b, c, d) {
  CommandHandler(
    ..handler,
    event_filter: facts.event_filter(facts),
    context_reducer: facts.build_context(facts),
  )
}

pub fn with_enriched_context(
  handler: command_handler.CommandHandler(e, f, g, h),
  f: fn(pog.Connection, g) -> Result(g, String),
) -> command_handler.CommandHandler(e, f, g, h) {
  CommandHandler(..handler, enrich_context: f)
}

pub fn with_metadata(
  handler: command_handler.CommandHandler(i, j, k, l),
  f: fn(i, k) -> dict.Dict(String, String),
) -> command_handler.CommandHandler(i, j, k, l) {
  CommandHandler(..handler, metadata_generator: f)
}

pub fn make_handler(
  initial_context: context,
  facts: List(Fact(TicketEvent, context)),
  execute: fn(command, context) -> Result(List(TicketEvent), error),
) -> command_handler.CommandHandler(command, TicketEvent, context, error) {
  handler(initial_context, execute)
  |> with_facts(facts)
  |> with_metadata(metadata)
}

fn metadata(_command, _context) {
  dict.from_list([
    #("source", "ticket_service"),
    #("version", "1"),
  ])
}
