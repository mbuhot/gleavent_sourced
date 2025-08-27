import gleam/result
import gleavent_sourced/command_handler
import gleavent_sourced/customer_support/ticket_commands.{
  type MarkDuplicateCommand, type TicketError,
}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/customer_support/ticket_facts.{type DuplicateStatus}

pub type MarkDuplicateContext {
  MarkDuplicateContext(
    original_ticket_exists: Bool,
    original_ticket_closed: Bool,
    duplicate_ticket_exists: Bool,
    duplicate_ticket_status: DuplicateStatus,
  )
}

pub fn create_mark_duplicate_handler(
  command: MarkDuplicateCommand,
) -> command_handler.CommandHandler(
  MarkDuplicateCommand,
  TicketEvent,
  MarkDuplicateContext,
  TicketError,
) {
  let handler_facts = [
    ticket_facts.exists(
      command.original_ticket_id,
      fn(ctx, original_ticket_exists) {
        MarkDuplicateContext(..ctx, original_ticket_exists:)
      },
    ),
    ticket_facts.is_closed(
      command.original_ticket_id,
      fn(ctx, original_ticket_closed) {
        MarkDuplicateContext(..ctx, original_ticket_closed:)
      },
    ),
    ticket_facts.exists(
      command.duplicate_ticket_id,
      fn(ctx, duplicate_ticket_exists) {
        MarkDuplicateContext(..ctx, duplicate_ticket_exists:)
      },
    ),
    ticket_facts.duplicate_status(
      command.duplicate_ticket_id,
      fn(ctx, duplicate_ticket_status) {
        MarkDuplicateContext(..ctx, duplicate_ticket_status:)
      },
    ),
  ]

  ticket_commands.make_handler(
    handler_facts,
    MarkDuplicateContext(
      original_ticket_exists: False,
      original_ticket_closed: False,
      duplicate_ticket_exists: False,
      duplicate_ticket_status: ticket_facts.Unique,
    ),
    mark_duplicate_logic,
  )
}

fn mark_duplicate_logic(
  command: MarkDuplicateCommand,
  context: MarkDuplicateContext,
) -> Result(List(TicketEvent), TicketError) {
  use _ <- result.try(validate_original_ticket_exists(context))
  use _ <- result.try(validate_duplicate_ticket_exists(context))
  use _ <- result.try(validate_not_already_duplicate(context))

  // All validations pass - create the event
  let event =
    ticket_events.TicketMarkedDuplicate(
      duplicate_ticket_id: command.duplicate_ticket_id,
      original_ticket_id: command.original_ticket_id,
      marked_at: command.marked_at,
    )
  Ok([event])
}

fn validate_original_ticket_exists(
  context: MarkDuplicateContext,
) -> Result(Nil, TicketError) {
  case context.original_ticket_exists {
    False ->
      Error(ticket_commands.BusinessRuleViolation(
        "Original ticket does not exist",
      ))
    True -> Ok(Nil)
  }
}

fn validate_duplicate_ticket_exists(
  context: MarkDuplicateContext,
) -> Result(Nil, TicketError) {
  case context.duplicate_ticket_exists {
    False ->
      Error(ticket_commands.BusinessRuleViolation(
        "Duplicate ticket does not exist",
      ))
    True -> Ok(Nil)
  }
}

fn validate_not_already_duplicate(
  context: MarkDuplicateContext,
) -> Result(Nil, TicketError) {
  case context.duplicate_ticket_status {
    ticket_facts.DuplicateOf(_) ->
      Error(ticket_commands.BusinessRuleViolation(
        "Ticket is already marked as duplicate",
      ))
    _ -> Ok(Nil)
  }
}
