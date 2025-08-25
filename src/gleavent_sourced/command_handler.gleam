import gleam/dict.{type Dict}
import gleam/result
import gleavent_sourced/event_filter.{type EventFilter}
import pog

// Generic command handler definition
pub type CommandHandler(command, event, context, error) {
  CommandHandler(
    event_filter: fn(command) -> EventFilter,
    context_reducer: fn(List(event), context) -> context,
    initial_context: context,
    command_logic: fn(command, context) -> Result(List(event), error),
  )
}

// Command processing result
pub type CommandResult(event, error) {
  CommandAccepted(events: List(event))
  CommandRejected(error: error)
  CommandFailed(system_error: String)
}

// Command router for dispatching
pub type CommandRouter(command, event, context, error) {
  CommandRouter(handlers: Dict(String, CommandHandler(command, event, context, error)))
}

// Create a new empty command router
pub fn new() -> CommandRouter(command, event, context, error) {
  CommandRouter(handlers: dict.new())
}

// Register a command handler with the router
pub fn register_handler(
  router: CommandRouter(command, event, context, error),
  command_type: String,
  handler: CommandHandler(command, event, context, error),
) -> CommandRouter(command, event, context, error) {
  CommandRouter(handlers: dict.insert(router.handlers, command_type, handler))
}

// Handle a command using the appropriate handler
pub fn handle_command(
  router: CommandRouter(command, event, context, error),
  db: pog.Connection,
  command_type: String,
  command: command,
) -> Result(CommandResult(event, error), String) {
  case dict.get(router.handlers, command_type) {
    Error(_) -> Error("Handler not found for command type: " <> command_type)
    Ok(handler) -> {
      // For now, implement simple command processing without event loading/conflicts
      // Just execute the command logic directly with initial context
      case handler.command_logic(command, handler.initial_context) {
        Ok(events) -> Ok(CommandAccepted(events))
        Error(business_error) -> Ok(CommandRejected(business_error))
      }
    }
  }
}
