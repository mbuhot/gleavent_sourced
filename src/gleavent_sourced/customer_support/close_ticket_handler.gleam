import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type CloseTicketCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events.{type TicketEvent}
import gleavent_sourced/customer_support/ticket_facts
import gleavent_sourced/facts
import gleavent_sourced/validation.{require, validate}
import pog

// Context built from facts to validate ticket closing business rules
// Contains validation state for the ticket being closed
pub type TicketCloseContext {
  TicketCloseContext(
    exists: Bool,
    is_closed: Bool,
    current_assignee: Option(String),
    priority: Option(String),
    linked_children: List(String),
    open_children: List(String),
  )
}

// Default context state before loading events - assumes ticket doesn't exist
fn initial_context() {
  TicketCloseContext(
    exists: False,
    is_closed: False,
    current_assignee: None,
    priority: None,
    linked_children: [],
    open_children: [],
  )
}

// Define facts needed to validate ticket closing
fn facts(ticket_id: String) {
  [
    ticket_facts.exists(ticket_id, fn(ctx, exists) {
      TicketCloseContext(..ctx, exists:)
    }),
    ticket_facts.current_assignee(ticket_id, fn(ctx, current_assignee) {
      TicketCloseContext(..ctx, current_assignee:)
    }),
    ticket_facts.is_closed(ticket_id, fn(ctx, is_closed) {
      TicketCloseContext(..ctx, is_closed:)
    }),
    ticket_facts.priority(ticket_id, fn(ctx, priority) {
      TicketCloseContext(..ctx, priority:)
    }),
    ticket_facts.child_tickets(ticket_id, fn(ctx, linked_children) {
      TicketCloseContext(..ctx, linked_children:)
    }),
  ]
}

// Creates command handler with facts to validate ticket before closing
// Uses tagged event isolation to efficiently load ticket state
pub fn create_close_ticket_handler(
  command: CloseTicketCommand,
) -> CommandHandler(
  CloseTicketCommand,
  TicketEvent,
  TicketCloseContext,
  TicketError,
) {
  ticket_commands.handler(initial_context(), execute)
  |> ticket_commands.with_facts(facts(command.ticket_id))
  |> ticket_commands.with_enriched_context(enrich_context)
}

// Second step: filter out closed children from linked children
fn enrich_context(
  db: pog.Connection,
  context: TicketCloseContext,
) -> Result(TicketCloseContext, String) {
  case context.linked_children {
    [] -> Ok(context)
    children -> {
      // build list of facts to query
      let child_facts =
        list.map(children, fn(child_id) {
          ticket_facts.is_closed(child_id, fn(ctx, is_closed) {
            [#(child_id, is_closed), ..ctx]
          })
        })

      // query event log for all child fact results
      use results <- result.try(
        child_facts
        |> facts.query_event_log(db, _, [], ticket_events.decode)
        |> result.map_error(fn(_) {
          "Failed to query child ticket closure status"
        }),
      )

      // Filter down to open children
      let open_children =
        list.filter_map(results, fn(result) {
          case result {
            #(child_id, True) -> Ok(child_id)
            _ -> Error(Nil)
          }
        })

      Ok(TicketCloseContext(..context, open_children: open_children))
    }
  }
}

// Core business logic - validates rules then creates TicketClosed event
fn execute(
  command: CloseTicketCommand,
  context: TicketCloseContext,
) -> Result(List(TicketEvent), TicketError) {
  use _ <- validate(ticket_exists, context)
  use _ <- validate(ticket_not_already_closed, context)
  use _ <- validate(no_open_children, context)
  use _ <- validate(closer_permissions(_, command.closed_by), context)
  use _ <- validate(resolution_detail(_, command.resolution), context)
  use _ <- validate(closed_at, command.closed_at)
  Ok([
    ticket_events.TicketClosed(
      command.ticket_id,
      command.resolution,
      command.closed_at,
    ),
  ])
}

// Validates the ticket exists before allowing closure
fn ticket_exists(context: TicketCloseContext) -> Result(Nil, TicketError) {
  require(context.exists, BusinessRuleViolation("Ticket does not exist"))
}

// Validates the ticket is not already closed
fn ticket_not_already_closed(
  context: TicketCloseContext,
) -> Result(Nil, TicketError) {
  require(!context.is_closed, BusinessRuleViolation("Ticket is already closed"))
}

// Validates only the assignee can close the ticket
fn closer_permissions(
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

// Validates resolution meets requirements based on ticket priority
fn resolution_detail(
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

// Validates the ticket has no open child tickets
fn no_open_children(context: TicketCloseContext) -> Result(Nil, TicketError) {
  require(
    context.open_children == [],
    BusinessRuleViolation("Cannot close parent ticket with open child tickets"),
  )
}

// Validates the closed_at timestamp is not empty
fn closed_at(closed_at: String) -> Result(Nil, TicketError) {
  require(closed_at != "", BusinessRuleViolation("Closed at cannot be empty"))
}
