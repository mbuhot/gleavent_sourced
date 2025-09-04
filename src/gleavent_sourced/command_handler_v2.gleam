import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/json
import gleam/result
import gleam/string
import gleavent_sourced/facts_v2.{type Fact}
import pog

// Simplified command handler using the new facts system
pub type CommandHandlerV2(command, event, context, error) {
  CommandHandlerV2(
    initial_context: context,
    facts: List(Fact(context, event)),
    execute: fn(command, context) -> Result(List(event), error),
    event_decoder: fn(String, Dynamic) -> Result(event, String),
    event_encoder: fn(event) -> #(String, json.Json),
  )
}

// Command processing result
pub type CommandResult(event, error) {
  CommandAccepted(events: List(event))
  CommandRejected(error: error)
  CommandFailed(system_error: String)
}

// Create a command handler with facts-based approach
pub fn new(
  initial_context: context,
  facts: List(Fact(context, event)),
  execute: fn(command, context) -> Result(List(event), error),
  event_decoder: fn(String, Dynamic) -> Result(event, String),
  event_encoder: fn(event) -> #(String, json.Json),
) -> CommandHandlerV2(command, event, context, error) {
  CommandHandlerV2(
    initial_context: initial_context,
    facts: facts,
    execute: execute,
    event_decoder: event_decoder,
    event_encoder: event_encoder,
  )
}

// Execute command with automatic retry on conflicts
pub fn execute(
  db: pog.Connection,
  handler: CommandHandlerV2(command, event, context, error),
  command: command,
  metadata: dict.Dict(String, String),
) -> Result(CommandResult(event, error), String) {
  execute_with_retries(db, handler, command, metadata, 3)
}

// Execute with custom retry count
pub fn execute_with_retries(
  db: pog.Connection,
  handler: CommandHandlerV2(command, event, context, error),
  command: command,
  metadata: dict.Dict(String, String),
  retries_left: Int,
) -> Result(CommandResult(event, error), String) {
  // Load context using facts
  use #(context, max_sequence) <- result.try(
    facts_v2.query_event_log_with_sequence(
      db,
      handler.facts,
      handler.initial_context,
      handler.event_decoder,
    )
    |> result.map_error(fn(e) {
      "Failed to load context: " <> string.inspect(e)
    }),
  )

  // Execute command logic
  case handler.execute(command, context) {
    Error(business_error) -> Ok(CommandRejected(business_error))
    Ok(events) -> {
      use append_result <- result.try(append_events_with_consistency_check(
        db,
        handler,
        command,
        context,
        events,
        metadata,
        max_sequence,
      ))

      case append_result {
        facts_v2.AppendSuccess -> Ok(CommandAccepted(events))
        facts_v2.AppendConflict -> {
          case retries_left {
            0 -> Error("Maximum retries exceeded due to conflicts")
            _ ->
              execute_with_retries(
                db,
                handler,
                command,
                metadata,
                retries_left - 1,
              )
          }
        }
      }
    }
  }
}

// Helper to append events with conflict detection
fn append_events_with_consistency_check(
  db: pog.Connection,
  handler: CommandHandlerV2(command, event, context, error),
  command: command,
  context: context,
  events: List(event),
  metadata: dict.Dict(String, String),
  max_sequence: Int,
) -> Result(facts_v2.AppendResult, String) {
  facts_v2.append_events(
    db,
    events,
    handler.event_encoder,
    metadata,
    handler.facts,
    max_sequence,
  )
  |> result.map_error(fn(e) { "Failed to append events: " <> string.inspect(e) })
}
