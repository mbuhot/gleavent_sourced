import gleam/string
import gleam/dict
import gleam/list
import gleam/option
import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/customer_support/ticket_commands.{
  type BulkAssignCommand, type TicketError, BusinessRuleViolation,
}
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts
import gleavent_sourced/validation.{require, validate}

// Context for bulk assignment containing validation state for all tickets
pub type BulkAssignContext {
  BulkAssignContext(ticket_states: dict.Dict(String, TicketState))
}

pub type TicketState {
  TicketState(
    ticket_id: String,
    exists: Bool,
    is_closed: Bool,
    current_assignee: String,
  )
}

// Default context state before loading events
fn initial_context() {
  BulkAssignContext(ticket_states: dict.new())
}

// Helper function to update a specific ticket's state in the context
fn update_ticket(
  context: BulkAssignContext,
  ticket_id: String,
  update_fn: fn(TicketState) -> TicketState,
) -> BulkAssignContext {
    context.ticket_states
    |> dict.upsert(ticket_id, fn (v) {
      option.unwrap(v, TicketState(ticket_id, False, False, ""))
      |> update_fn()
    })
    |> BulkAssignContext(ticket_states: _)
}

// Define facts needed to validate bulk assignment
fn facts(ticket_ids: List(String)) {
  use ticket_id <- list.flat_map(ticket_ids)
  [
    ticket_facts.exists(ticket_id, fn(ctx: BulkAssignContext, exists) {
      use state <- update_ticket(ctx, ticket_id)
      TicketState(..state, exists:)
    }),
    ticket_facts.is_closed(ticket_id, fn(ctx: BulkAssignContext, is_closed) {
      use state <- update_ticket(ctx, ticket_id)
      TicketState(..state, is_closed:)
    }),
    ticket_facts.current_assignee(
      ticket_id,
      fn(ctx: BulkAssignContext, current_assignee_opt) {
        let current_assignee = current_assignee_opt |> option.unwrap("")
        use state <- update_ticket(ctx, ticket_id)
        TicketState(..state, current_assignee:)
      },
    ),
  ]
}

// Creates command handler for bulk assignment
pub fn create_bulk_assign_handler(
  command: BulkAssignCommand,
) -> CommandHandler(
  BulkAssignCommand,
  ticket_events.TicketEvent,
  BulkAssignContext,
  TicketError,
) {
  ticket_commands.handler(initial_context(), execute)
  |> ticket_commands.with_facts(facts(command.ticket_ids))
}

// Core business logic - validates rules then creates TicketAssigned events
fn execute(
  command: BulkAssignCommand,
  context: BulkAssignContext,
) -> Result(List(ticket_events.TicketEvent), TicketError) {
  use _ <- validate(all_tickets_exist, context)
  use _ <- validate(no_tickets_closed, context)
  use _ <- validate(assignee_valid(_, command.assignee), context)

  // Create TicketAssigned event for each ticket
  let events =
    command.ticket_ids
    |> list.map(fn(ticket_id) {
      ticket_events.TicketAssigned(
        ticket_id: ticket_id,
        assignee: command.assignee,
        assigned_at: command.assigned_at,
      )
    })

  Ok(events)
}

// Validates all tickets exist before allowing bulk assignment
fn all_tickets_exist(context: BulkAssignContext) -> Result(Nil, TicketError) {
  let non_existent_tickets =
    context.ticket_states
    |> dict.to_list()
    |> list.filter_map(fn(entry) {
      let #(ticket_id, state) = entry
      case state.exists {
        False -> Ok(ticket_id)
        True -> Error(Nil)
      }
    })

  case non_existent_tickets {
    [] -> Ok(Nil)
    missing -> {
      Error(BusinessRuleViolation("Tickets do not exist: " <> string.join(missing, ", ")))
    }
  }
}

// Validates no tickets are closed
fn no_tickets_closed(context: BulkAssignContext) -> Result(Nil, TicketError) {
  let closed_tickets =
    context.ticket_states
    |> dict.to_list()
    |> list.filter_map(fn(entry) {
      let #(ticket_id, state) = entry
      case state.is_closed {
        True -> Ok(ticket_id)
        False -> Error(Nil)
      }
    })

  case closed_tickets {
    [] -> Ok(Nil)
    closed -> {
      Error(BusinessRuleViolation(
        "Cannot assign closed tickets: " <> string.join(closed, ", "),
      ))
    }
  }
}

// Validates assignee is valid
fn assignee_valid(
  _context: BulkAssignContext,
  assignee: String,
) -> Result(Nil, TicketError) {
  require(assignee != "", BusinessRuleViolation("Assignee cannot be empty"))
}
