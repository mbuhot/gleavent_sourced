import gleam/option.{type Option}

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
