import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/json
import gleam/result
import gleavent_sourced/event_filter.{type EventFilter}
import gleavent_sourced/event_log
import pog

// Generic command handler definition
pub type CommandHandler(command, event, context, error) {
  CommandHandler(
    event_filter: fn(command) -> EventFilter,
    context_reducer: fn(List(event), context) -> context,
    initial_context: context,
    command_logic: fn(command, context) -> Result(List(event), error),
    event_mapper: fn(String, Dynamic) -> Result(event, String),
    event_converter: fn(event) -> #(String, json.Json),
    metadata_generator: fn(command, context) -> Dict(String, String),
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
  CommandRouter(
    handlers: Dict(String, CommandHandler(command, event, context, error)),
  )
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
      // Retry loop for optimistic concurrency control
      handle_with_retry(db, handler, command, 3)
    }
  }
}

fn load_events_and_build_context(
  db: pog.Connection,
  handler: CommandHandler(command, event, context, error),
  command: command,
) -> Result(#(context, Int, EventFilter), String) {
  let filter = handler.event_filter(command)

  use #(loaded_events, max_seq) <- result.try(
    event_log.query_events(db, filter, handler.event_mapper)
    |> result.map_error(fn(_) { "Failed to load events for command processing" }),
  )

  let context = handler.context_reducer(loaded_events, handler.initial_context)
  Ok(#(context, max_seq, filter))
}

fn append_events_with_conflict_detection(
  db: pog.Connection,
  handler: CommandHandler(command, event, context, error),
  command: command,
  context: context,
  events: List(event),
  filter: EventFilter,
  max_seq: Int,
) -> Result(event_log.AppendResult, String) {
  event_log.append_events(
    db,
    events,
    handler.event_converter,
    handler.metadata_generator(command, context),
    filter,
    max_seq,
  )
  |> result.map_error(fn(_) { "Failed to append events" })
}

// Internal function to handle command with retry logic
fn handle_with_retry(
  db: pog.Connection,
  handler: CommandHandler(command, event, context, error),
  command: command,
  retries_left: Int,
) -> Result(CommandResult(event, error), String) {
  use #(context, max_seq, filter) <- result.try(load_events_and_build_context(
    db,
    handler,
    command,
  ))

  case handler.command_logic(command, context) {
    Error(business_error) -> Ok(CommandRejected(business_error))
    Ok(events) -> {
      use append_result <- result.try(append_events_with_conflict_detection(
        db,
        handler,
        command,
        context,
        events,
        filter,
        max_seq,
      ))

      case append_result {
        event_log.AppendSuccess -> Ok(CommandAccepted(events))
        event_log.AppendConflict(_count) -> {
          case retries_left {
            0 -> Error("Maximum retries exceeded due to conflicts")
            _ -> handle_with_retry(db, handler, command, retries_left - 1)
          }
        }
      }
    }
  }
}
