import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/list

import gleavent_sourced/connection_pool
import gleavent_sourced/parrot_pog
import gleavent_sourced/sql
import gleavent_sourced/test_runner

import pog

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/event_persistence_test"])
}

pub fn append_and_read_event_test() {
  // Set up database connection pool
  let pool_name = process.new_name("test_pool")
  let assert Ok(_supervisor_pid) = connection_pool.start_supervisor(pool_name)
  let db = pog.named_connection(pool_name)

  // Clear events table for clean test state
  let truncate_query = pog.query("TRUNCATE TABLE events RESTART IDENTITY")
  let assert Ok(_) = pog.execute(truncate_query, on: db)

  // Create test event data
  let event_type = "test_event"
  let payload_json =
    json.object([
      #("message", json.string("Hello, World!")),
      #("count", json.int(42)),
    ])
  let metadata_json =
    json.object([#("source", json.string("test")), #("version", json.int(1))])

  // Convert JSON to strings for JSONB storage
  let payload_str = json.to_string(payload_json)
  let metadata_str = json.to_string(metadata_json)

  // Get the SQL and parameters for inserting an event
  let #(insert_sql, insert_params) =
    sql.append_event(
      event_type: event_type,
      payload: payload_str,
      metadata: metadata_str,
    )

  // Convert parrot params to pog values and build query
  let insert_query =
    pog.query(insert_sql)
    |> parrot_pog.parameters(insert_params)

  // Execute the insert
  let assert Ok(_) = pog.execute(insert_query, on: db)

  // Get the SQL for reading events
  let #(select_sql, _select_params, _decoder) = sql.read_all_events()

  // Create pog query for select
  let select_query =
    pog.query(select_sql)
    |> pog.returning(sql.read_all_events_decoder())

  // Execute the select
  let assert Ok(returned) = pog.execute(select_query, on: db)

  // Extract rows from returned result
  let rows = returned.rows

  // Verify we got at least one event back
  let assert Ok(event) = list.first(rows)

  // Verify the event data matches what we inserted
  assert event.event_type == event_type

  // Create decoders for JSON payload verification
  let payload_decoder = {
    use message <- decode.field("message", decode.string)
    use count <- decode.field("count", decode.int)
    decode.success(#(message, count))
  }

  let metadata_decoder = {
    use source <- decode.field("source", decode.string)
    use version <- decode.field("version", decode.int)
    decode.success(#(source, version))
  }

  // Parse and verify payload
  let assert Ok(#(message, count)) = json.parse(event.payload, payload_decoder)
  assert message == "Hello, World!"
  assert count == 42

  // Parse and verify metadata
  let assert Ok(#(source, version)) =
    json.parse(event.metadata, metadata_decoder)
  assert source == "test"
  assert version == 1
}
