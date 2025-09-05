import gleam/dict
import gleavent_sourced/command_handler.{type CommandResult}
import gleavent_sourced/customer_support/assign_ticket_handler
import gleavent_sourced/customer_support/bulk_assign_handler
import gleavent_sourced/customer_support/close_ticket_handler
import gleavent_sourced/customer_support/mark_duplicate_handler
import gleavent_sourced/customer_support/open_ticket_handler
import gleavent_sourced/customer_support/ticket_commands.{
  type AssignTicketCommand, type BulkAssignCommand, type CloseTicketCommand,
  type MarkDuplicateCommand, type OpenTicketCommand, type TicketError,
}
import gleavent_sourced/customer_support/ticket_events
import pog

// Union type for all ticket commands
pub type TicketCommand {
  OpenTicket(OpenTicketCommand)
  AssignTicket(AssignTicketCommand)
  CloseTicket(CloseTicketCommand)
  MarkDuplicate(MarkDuplicateCommand)
  BulkAssign(BulkAssignCommand)
}

// Router function - pattern matches on command type and delegates to appropriate handler
pub fn handle_ticket_command(
  command: TicketCommand,
  db: pog.Connection,
) -> Result(CommandResult(ticket_events.TicketEvent, TicketError), String) {
  let metadata = dict.new()

  case command {
    OpenTicket(open_cmd) -> {
      let handler = open_ticket_handler.create_open_ticket_handler()
      command_handler.execute(db, handler, open_cmd, metadata)
    }
    AssignTicket(assign_cmd) -> {
      let handler =
        assign_ticket_handler.create_assign_ticket_handler(assign_cmd)
      command_handler.execute(db, handler, assign_cmd, metadata)
    }
    CloseTicket(close_cmd) -> {
      let handler = close_ticket_handler.create_close_ticket_handler(close_cmd)
      command_handler.execute(db, handler, close_cmd, metadata)
    }
    MarkDuplicate(mark_cmd) -> {
      let handler =
        mark_duplicate_handler.create_mark_duplicate_handler(mark_cmd)
      command_handler.execute(db, handler, mark_cmd, metadata)
    }
    BulkAssign(bulk_cmd) -> {
      let handler = bulk_assign_handler.create_bulk_assign_handler(bulk_cmd)
      command_handler.execute(db, handler, bulk_cmd, metadata)
    }
  }
}
