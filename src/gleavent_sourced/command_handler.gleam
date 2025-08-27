import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/json

import gleam/result
import gleavent_sourced/event_filter.{type EventFilter}
import gleavent_sourced/event_log

import pog

// Generic command handler definition
pub type CommandHandler(command, event, context, error) {
  CommandHandler(
    event_filter: EventFilter,
    context_reducer: fn(dict.Dict(String, List(event)), context) -> context,
    initial_context: context,
    command_logic: fn(command, context) -> Result(List(event), error),
    event_mapper: fn(String, Dynamic) -> Result(event, String),
    event_converter: fn(event) -> #(String, json.Json),
    metadata_generator: fn(command, context) -> dict.Dict(String, String),
  )
}

// Command processing result
pub type CommandResult(event, error) {
  CommandAccepted(events: List(event))
  CommandRejected(error: error)
  CommandFailed(system_error: String)
}

fn load_events_and_build_context(
  db: pog.Connection,
  handler: CommandHandler(command, event, context, error),
) -> Result(#(context, Int, EventFilter), String) {
  let filter = handler.event_filter

  use #(events_by_fact, max_seq) <- result.try(
    event_log.query_events_with_tags(db, filter, handler.event_mapper)
    |> result.map_error(fn(_) {
      "Failed to load tagged events for command processing"
    }),
  )

  // Let the context_reducer handle the tagged events
  let context = handler.context_reducer(events_by_fact, handler.initial_context)

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

// Public function to handle command with retry logic
pub fn execute(
  db: pog.Connection,
  handler: CommandHandler(command, event, context, error),
  command: command,
  retries_left: Int,
) -> Result(CommandResult(event, error), String) {
  use #(context, max_seq, filter) <- result.try(load_events_and_build_context(
    db,
    handler,
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
            _ -> execute(db, handler, command, retries_left - 1)
          }
        }
      }
    }
  }
}
