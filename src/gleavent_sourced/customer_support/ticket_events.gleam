import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import gleam/result

pub type TicketEvent {
  TicketOpened(
    ticket_id: String,
    title: String,
    description: String,
    priority: String,
  )
  TicketAssigned(ticket_id: String, assignee: String, assigned_at: String)
  TicketClosed(ticket_id: String, resolution: String, closed_at: String)
  TicketMarkedDuplicate(
    duplicate_ticket_id: String,
    original_ticket_id: String,
    marked_at: String,
  )
}

pub fn encode(event: TicketEvent) -> #(String, json.Json) {
  case event {
    TicketOpened(ticket_id, title, description, priority) -> {
      let payload =
        json.object([
          #("ticket_id", json.string(ticket_id)),
          #("title", json.string(title)),
          #("description", json.string(description)),
          #("priority", json.string(priority)),
        ])
      #("TicketOpened", payload)
    }
    TicketAssigned(ticket_id, assignee, assigned_at) -> {
      let payload =
        json.object([
          #("ticket_id", json.string(ticket_id)),
          #("assignee", json.string(assignee)),
          #("assigned_at", json.string(assigned_at)),
        ])
      #("TicketAssigned", payload)
    }
    TicketClosed(ticket_id, resolution, closed_at) -> {
      let payload =
        json.object([
          #("ticket_id", json.string(ticket_id)),
          #("resolution", json.string(resolution)),
          #("closed_at", json.string(closed_at)),
        ])
      #("TicketClosed", payload)
    }
    TicketMarkedDuplicate(duplicate_ticket_id, original_ticket_id, marked_at) -> {
      let payload =
        json.object([
          #("duplicate_ticket_id", json.string(duplicate_ticket_id)),
          #("original_ticket_id", json.string(original_ticket_id)),
          #("marked_at", json.string(marked_at)),
        ])
      #("TicketMarkedDuplicate", payload)
    }
  }
}

pub fn decode(event_type: String, payload_dynamic: Dynamic) {
  let decode_with = fn(decoder) {
    decode.run(payload_dynamic, decoder)
    |> result.map_error(fn(_) { "Failed to decode " <> event_type })
  }

  case event_type {
    "TicketOpened" -> decode_with(ticket_opened_decoder())
    "TicketAssigned" -> decode_with(ticket_assigned_decoder())
    "TicketClosed" -> decode_with(ticket_closed_decoder())
    "TicketMarkedDuplicate" -> decode_with(ticket_marked_duplicate_decoder())
    _ -> Error("Unknown event type: " <> event_type)
  }
}

pub fn ticket_opened_decoder() -> decode.Decoder(TicketEvent) {
  use ticket_id <- decode.field("ticket_id", decode.string)
  use title <- decode.field("title", decode.string)
  use description <- decode.field("description", decode.string)
  use priority <- decode.field("priority", decode.string)
  decode.success(TicketOpened(ticket_id, title, description, priority))
}

pub fn ticket_assigned_decoder() -> decode.Decoder(TicketEvent) {
  use ticket_id <- decode.field("ticket_id", decode.string)
  use assignee <- decode.field("assignee", decode.string)
  use assigned_at <- decode.field("assigned_at", decode.string)
  decode.success(TicketAssigned(ticket_id, assignee, assigned_at))
}

pub fn ticket_closed_decoder() -> decode.Decoder(TicketEvent) {
  use ticket_id <- decode.field("ticket_id", decode.string)
  use resolution <- decode.field("resolution", decode.string)
  use closed_at <- decode.field("closed_at", decode.string)
  decode.success(TicketClosed(ticket_id, resolution, closed_at))
}

pub fn ticket_marked_duplicate_decoder() -> decode.Decoder(TicketEvent) {
  use duplicate_ticket_id <- decode.field("duplicate_ticket_id", decode.string)
  use original_ticket_id <- decode.field("original_ticket_id", decode.string)
  use marked_at <- decode.field("marked_at", decode.string)
  decode.success(TicketMarkedDuplicate(
    duplicate_ticket_id,
    original_ticket_id,
    marked_at,
  ))
}
