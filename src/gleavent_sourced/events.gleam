import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

import gleam/time/timestamp.{type Timestamp}
import gleavent_sourced/sql

pub type Event(payload) {
  Event(
    sequence_number: Int,
    occurred_at: Timestamp,
    event_type: String,
    payload: payload,
    metadata: String,
  )
}

pub fn decode_payloads(
  raw_events: List(sql.ReadEventsByTypes),
  payload_decoder: decode.Decoder(payload),
) -> Result(List(Event(payload)), json.DecodeError) {
  list.try_map(raw_events, fn(raw_event) {
    json.parse(raw_event.payload, payload_decoder)
    |> result.map(fn(decoded_payload) {
      Event(
        sequence_number: raw_event.sequence_number,
        occurred_at: raw_event.occurred_at,
        event_type: raw_event.event_type,
        payload: decoded_payload,
        metadata: raw_event.metadata,
      )
    })
  })
}
