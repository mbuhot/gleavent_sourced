import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleavent_sourced/command_handler_v2
import gleavent_sourced/customer_support/ticket_events
import gleavent_sourced/customer_support/ticket_facts_v2
import gleavent_sourced/facts_v2
import gleavent_sourced/test_runner
import pog

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/command_handler_v2_test"])
}

pub type TestCommand {
  TestCommand(ticket_id: String, assignee: String)
}

pub type TestContext {
  TestContext(
    ticket_exists: Bool,
    ticket_closed: Bool,
    current_assignee: option.Option(String),
  )
}

pub type TestError {
  TestError(message: String)
}

pub fn command_rejection_test() {
  test_runner.txn(fn(db) {
    let initial_context =
      TestContext(
        ticket_exists: False,
        ticket_closed: False,
        current_assignee: option.None,
      )
    let facts = [
      ticket_facts_v2.exists("ticket-1", fn(ctx, exists) {
        TestContext(..ctx, ticket_exists: exists)
      }),
    ]
    let execute = fn(_command, context: TestContext) {
      case context.ticket_exists {
        True ->
          Ok([
            ticket_events.TicketAssigned(
              "ticket-1",
              "user-1",
              "2024-01-01T00:00:00Z",
            ),
          ])
        False -> Error(TestError("Ticket does not exist"))
      }
    }

    let handler =
      command_handler_v2.new(
        initial_context,
        facts,
        execute,
        ticket_events.decode,
        ticket_events.encode,
      )

    let command = TestCommand("ticket-1", "user-1")

    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, dict.new())

    case result {
      command_handler_v2.CommandRejected(TestError(message)) -> {
        assert message == "Ticket does not exist"
      }
      _ -> panic as "Expected command to be rejected for non-existent ticket"
    }
  })
}

pub fn command_success_and_persistence_test() {
  test_runner.txn(fn(db) {
    // First, create a ticket so it exists
    let ticket_opened =
      ticket_events.TicketOpened(
        "ticket-1",
        "Test ticket",
        "Test description",
        "high",
      )
    let assert Ok(_) =
      facts_v2.append_events(
        db,
        [ticket_opened],
        ticket_events.encode,
        dict.new(),
        [],
        0,
      )

    let initial_context =
      TestContext(
        ticket_exists: False,
        ticket_closed: False,
        current_assignee: option.None,
      )
    let facts = [
      ticket_facts_v2.exists("ticket-1", fn(ctx, exists) {
        TestContext(..ctx, ticket_exists: exists)
      }),
    ]
    let execute = fn(_command, context: TestContext) {
      case context.ticket_exists {
        True ->
          Ok([
            ticket_events.TicketAssigned(
              "ticket-1",
              "user-1",
              "2024-01-01T00:00:00Z",
            ),
          ])
        False -> Error(TestError("Ticket does not exist"))
      }
    }

    let handler =
      command_handler_v2.new(
        initial_context,
        facts,
        execute,
        ticket_events.decode,
        ticket_events.encode,
      )

    let command = TestCommand("ticket-1", "user-1")

    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, dict.new())

    // Verify command was accepted with correct events
    case result {
      command_handler_v2.CommandAccepted(events) -> {
        assert list.length(events) == 1
        case list.first(events) {
          Ok(ticket_events.TicketAssigned(ticket_id, assignee, _)) -> {
            assert ticket_id == "ticket-1"
            assert assignee == "user-1"
          }
          _ -> panic as "Expected TicketAssigned event"
        }
      }
      _ -> panic as "Expected command to be accepted for existing ticket"
    }

    // Verify the events were actually persisted to database
    let query =
      "SELECT COUNT(*) FROM events WHERE event_type = 'TicketAssigned'"
    let count_decoder = {
      use count <- decode.field(0, decode.int)
      decode.success(count)
    }
    let select_query = pog.query(query) |> pog.returning(count_decoder)
    let assert Ok(returned) = pog.execute(select_query, on: db)

    let count = case returned.rows {
      [count] -> count
      _ -> panic as "Expected exactly one result from COUNT query"
    }
    assert count == 1
  })
}

pub fn metadata_integration_test() {
  test_runner.txn(fn(db) {
    // First, create a ticket so it exists
    let ticket_opened =
      ticket_events.TicketOpened(
        "ticket-1",
        "Test ticket",
        "Test description",
        "high",
      )
    let assert Ok(_) =
      facts_v2.append_events(
        db,
        [ticket_opened],
        ticket_events.encode,
        dict.new(),
        [],
        0,
      )

    let initial_context =
      TestContext(
        ticket_exists: False,
        ticket_closed: False,
        current_assignee: option.None,
      )
    let facts = [
      ticket_facts_v2.exists("ticket-1", fn(ctx, exists) {
        TestContext(..ctx, ticket_exists: exists)
      }),
    ]
    let execute = fn(_command, context: TestContext) {
      case context.ticket_exists {
        True ->
          Ok([
            ticket_events.TicketAssigned(
              "ticket-1",
              "user-1",
              "2024-01-01T00:00:00Z",
            ),
          ])
        False -> Error(TestError("Ticket does not exist"))
      }
    }

    let handler =
      command_handler_v2.new(
        initial_context,
        facts,
        execute,
        ticket_events.decode,
        ticket_events.encode,
      )

    let command = TestCommand("ticket-1", "user-1")
    // System-level metadata that should be provided by the calling system
    let metadata =
      dict.from_list([
        #("user_id", "alice@example.com"),
        #("session_id", "sess_123456"),
        #("correlation_id", "corr_abc789"),
        #("source", "ticket_service"),
      ])

    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, metadata)

    // Verify command was accepted
    case result {
      command_handler_v2.CommandAccepted(events) -> {
        assert list.length(events) == 1
      }
      _ -> panic as "Expected command to be accepted"
    }

    // Verify the metadata was properly stored with the event
    let query =
      "SELECT metadata FROM events WHERE event_type = 'TicketAssigned' ORDER BY sequence_number DESC LIMIT 1"
    let metadata_decoder = {
      use metadata_json <- decode.field(0, decode.string)
      decode.success(metadata_json)
    }
    let select_query = pog.query(query) |> pog.returning(metadata_decoder)
    let assert Ok(returned) = pog.execute(select_query, on: db)

    case returned.rows {
      [metadata_json] -> {
        // Parse the JSON metadata and verify our system metadata was stored
        let metadata_decoder = {
          use user_id <- decode.field("user_id", decode.string)
          use session_id <- decode.field("session_id", decode.string)
          use correlation_id <- decode.field("correlation_id", decode.string)
          use source <- decode.field("source", decode.string)
          decode.success(#(user_id, session_id, correlation_id, source))
        }

        let assert Ok(#(user_id, session_id, correlation_id, source)) =
          json.parse(metadata_json, metadata_decoder)

        assert user_id == "alice@example.com"
        assert session_id == "sess_123456"
        assert correlation_id == "corr_abc789"
        assert source == "ticket_service"
      }
      _ -> panic as "Expected exactly one metadata record"
    }
  })
}

pub fn conflict_retry_behavior_test() {
  test_runner.txn(fn(db) {
    // Create a ticket first
    let ticket_opened =
      ticket_events.TicketOpened(
        "ticket-1",
        "Test ticket",
        "Test description",
        "high",
      )
    let assert Ok(_) =
      facts_v2.append_events(
        db,
        [ticket_opened],
        ticket_events.encode,
        dict.new(),
        [],
        0,
      )

    // Create handler with consistency facts that will detect assignment conflicts
    let initial_context =
      TestContext(
        ticket_exists: False,
        ticket_closed: False,
        current_assignee: option.None,
      )
    let facts = [
      ticket_facts_v2.exists("ticket-1", fn(ctx, exists) {
        TestContext(..ctx, ticket_exists: exists)
      }),
      ticket_facts_v2.current_assignee("ticket-1", fn(ctx, assignee) {
        TestContext(..ctx, current_assignee: assignee)
      }),
    ]
    let execute = fn(_command, context: TestContext) {
      case context.ticket_exists, context.current_assignee {
        True, option.None -> {
          // BREAK CONVENTION: Insert conflicting event during business logic!
          // This simulates a race condition where another process inserts an event
          // between when we loaded context and when we try to append our events
          let conflicting_assignment =
            ticket_events.TicketAssigned(
              "ticket-1",
              "concurrent_user",
              "2024-01-01T09:59:00Z",
            )
          let assert Ok(_) =
            facts_v2.append_events(
              db,
              [conflicting_assignment],
              ticket_events.encode,
              dict.new(),
              [],
              0,
            )

          // Return our events - this should cause conflict detection and retry!
          Ok([
            ticket_events.TicketAssigned(
              "ticket-1",
              "user-1",
              "2024-01-01T00:00:00Z",
            ),
          ])
        }
        True, option.Some(assignee) ->
          Error(TestError("Ticket already assigned to " <> assignee))
        False, _ -> Error(TestError("Ticket does not exist"))
      }
    }

    let handler =
      command_handler_v2.new(
        initial_context,
        facts,
        execute,
        ticket_events.decode,
        ticket_events.encode,
      )

    let command = TestCommand("ticket-1", "user-1")

    // This should be rejected on retry due to conflict detection
    let assert Ok(result) =
      command_handler_v2.execute(db, handler, command, dict.new())

    case result {
      command_handler_v2.CommandRejected(TestError(message)) -> {
        // Success! The retry mechanism detected the conflict and rejected the command
        assert message == "Ticket already assigned to concurrent_user"
      }
      _ -> panic as "Expected command to be rejected due to conflict"
    }

    // Verify only the conflicting event was persisted (our event was rejected)
    let query =
      "SELECT COUNT(*) FROM events WHERE event_type = 'TicketAssigned'"
    let count_decoder = {
      use count <- decode.field(0, decode.int)
      decode.success(count)
    }
    let select_query = pog.query(query) |> pog.returning(count_decoder)
    let assert Ok(returned) = pog.execute(select_query, on: db)

    let count = case returned.rows {
      [count] -> count
      _ -> panic as "Expected exactly one result from COUNT query"
    }
    assert count == 1
    // Only the conflicting event should exist
  })
}
