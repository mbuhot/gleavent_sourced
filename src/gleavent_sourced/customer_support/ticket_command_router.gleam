import gleam/dict
import gleavent_sourced/command_handler_v2.{type CommandResult}
import gleavent_sourced/customer_support/assign_ticket_handler_v2
import gleavent_sourced/customer_support/bulk_assign_handler_v2
import gleavent_sourced/customer_support/close_ticket_handler_v2
import gleavent_sourced/customer_support/mark_duplicate_handler_v2
import gleavent_sourced/customer_support/open_ticket_handler_v2
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
      let handler = open_ticket_handler_v2.create_open_ticket_handler_v2()
      command_handler_v2.execute(db, handler, open_cmd, metadata)
    }
    AssignTicket(assign_cmd) -> {
      let handler =
        assign_ticket_handler_v2.create_assign_ticket_handler_v2(assign_cmd)
      command_handler_v2.execute(db, handler, assign_cmd, metadata)
    }
    CloseTicket(close_cmd) -> {
      let handler = close_ticket_handler_v2.create_close_ticket_handler_v2(close_cmd)
      command_handler_v2.execute(db, handler, close_cmd, metadata)
    }
    MarkDuplicate(mark_cmd) -> {
      let handler =
        mark_duplicate_handler_v2.create_mark_duplicate_handler_v2(mark_cmd)
      command_handler_v2.execute(db, handler, mark_cmd, metadata)
    }
    BulkAssign(bulk_cmd) -> {
      let handler = bulk_assign_handler_v2.create_bulk_assign_handler_v2(bulk_cmd)
      command_handler_v2.execute(db, handler, bulk_cmd, metadata)
    }
  }
}
