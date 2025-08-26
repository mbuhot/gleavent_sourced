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
