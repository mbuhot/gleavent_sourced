import gleavent_sourced/command_handler_v2.{type CommandHandlerV2}
import gleavent_sourced/customer_support/ticket_commands.{
  type MarkDuplicateCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/customer_support/ticket_facts_v2
import gleavent_sourced/validation.{require, validate}

// Context built from facts to validate duplicate marking business rules
// Contains validation state for both tickets involved in the duplicate relationship
pub type MarkDuplicateContext {
  MarkDuplicateContext(
    original_ticket_exists: Bool,
    original_ticket_closed: Bool,
    duplicate_ticket_exists: Bool,
    duplicate_ticket_status: ticket_facts_v2.DuplicateStatus,
  )
}

// Default context state before loading events - assumes tickets don't exist
fn initial_context() {
  MarkDuplicateContext(
    original_ticket_exists: False,
    original_ticket_closed: False,
    duplicate_ticket_exists: False,
    duplicate_ticket_status: ticket_facts_v2.Unique,
  )
}

// Define facts needed to validate both tickets in the duplicate relationship
fn facts(original_ticket_id: String, duplicate_ticket_id: String) {
  [
    ticket_facts_v2.exists(original_ticket_id, fn(ctx, original_ticket_exists) {
      MarkDuplicateContext(..ctx, original_ticket_exists:)
    }),
    ticket_facts_v2.is_closed(original_ticket_id, fn(ctx, original_ticket_closed) {
      MarkDuplicateContext(..ctx, original_ticket_closed:)
    }),
    ticket_facts_v2.exists(duplicate_ticket_id, fn(ctx, duplicate_ticket_exists) {
      MarkDuplicateContext(..ctx, duplicate_ticket_exists:)
    }),
    ticket_facts_v2.duplicate_status(
      duplicate_ticket_id,
      fn(ctx, duplicate_ticket_status) {
        MarkDuplicateContext(..ctx, duplicate_ticket_status:)
      },
    ),
  ]
}

// Creates command handler with facts to validate both tickets before marking duplicate
// Uses strongly-typed facts system for efficient multi-ticket validation
pub fn create_mark_duplicate_handler_v2(
  command: MarkDuplicateCommand,
) -> CommandHandlerV2(
  MarkDuplicateCommand,
  TicketEvent,
  MarkDuplicateContext,
  TicketError,
) {
  command_handler_v2.new(
    initial_context(),
    facts(command.original_ticket_id, command.duplicate_ticket_id),
    execute,
    ticket_events.decode,
    ticket_events.encode,
  )
}

// Core business logic - validates rules then creates TicketMarkedDuplicate event
fn execute(
  command: MarkDuplicateCommand,
  context: MarkDuplicateContext,
) -> Result(List(TicketEvent), TicketError) {
  use _ <- validate(original_ticket_exists, context)
  use _ <- validate(duplicate_ticket_exists, context)
  use _ <- validate(not_self_reference, command)
  use _ <- validate(not_already_duplicate, context)

  // All validations pass - create the event
  let events = [
    ticket_events.TicketMarkedDuplicate(
      duplicate_ticket_id: command.duplicate_ticket_id,
      original_ticket_id: command.original_ticket_id,
      marked_at: command.marked_at,
    ),
  ]

  Ok(events)
}

// Validates the original ticket exists before allowing duplicate marking
fn original_ticket_exists(
  context: MarkDuplicateContext,
) -> Result(Nil, TicketError) {
  require(
    context.original_ticket_exists,
    BusinessRuleViolation("Original ticket does not exist"),
  )
}

// Validates the duplicate ticket exists before marking it as duplicate
fn duplicate_ticket_exists(
  context: MarkDuplicateContext,
) -> Result(Nil, TicketError) {
  require(
    context.duplicate_ticket_exists,
    BusinessRuleViolation("Duplicate ticket does not exist"),
  )
}

// Prevents marking a ticket as duplicate of itself
fn not_self_reference(
  command: MarkDuplicateCommand,
) -> Result(Nil, TicketError) {
  require(
    command.duplicate_ticket_id != command.original_ticket_id,
    BusinessRuleViolation("Ticket cannot be marked as duplicate of itself"),
  )
}

// Prevents marking a ticket as duplicate if it's already marked as one
fn not_already_duplicate(
  context: MarkDuplicateContext,
) -> Result(Nil, TicketError) {
  case context.duplicate_ticket_status {
    ticket_facts_v2.DuplicateOf(_) ->
      Error(BusinessRuleViolation("Ticket is already marked as duplicate"))
    _ -> Ok(Nil)
  }
}
