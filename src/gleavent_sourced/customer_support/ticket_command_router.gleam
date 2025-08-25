import gleavent_sourced/command_handler.{type CommandResult}
import gleavent_sourced/customer_support/assign_ticket_handler
import gleavent_sourced/customer_support/open_ticket_handler
import gleavent_sourced/customer_support/ticket_command_types.{
  type AssignTicketCommand, type CloseTicketCommand, type OpenTicketCommand,
  type TicketError,
}
import gleavent_sourced/customer_support/ticket_event
import pog

// Union type for all ticket commands
pub type TicketCommand {
  OpenTicket(OpenTicketCommand)
  AssignTicket(AssignTicketCommand)
  CloseTicket(CloseTicketCommand)
}

// Router function - pattern matches on command type and delegates to appropriate handler
pub fn handle_ticket_command(
  command: TicketCommand,
  db: pog.Connection,
) -> Result(CommandResult(ticket_event.TicketEvent, TicketError), String) {
  case command {
    OpenTicket(open_cmd) -> {
      let handler = open_ticket_handler.create_open_ticket_handler()
      command_handler.handle_with_retry(db, handler, open_cmd, 3)
    }
    AssignTicket(assign_cmd) -> {
      let handler = assign_ticket_handler.create_assign_ticket_handler()
      command_handler.handle_with_retry(db, handler, assign_cmd, 3)
    }
    CloseTicket(_close_cmd) -> {
      // TODO: implement close ticket handler
      Error("CloseTicket not implemented yet")
    }
  }
}
