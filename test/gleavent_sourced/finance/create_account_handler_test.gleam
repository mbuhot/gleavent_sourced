import gleam/dict
import gleam/time/timestamp
import gleavent_sourced/command_handler.{CommandAccepted, CommandRejected}
import gleavent_sourced/finance/account_commands.{
  CreateAccountCommand, BusinessRuleViolation,
}

import gleavent_sourced/finance/account_events.{AccountCreated}
import gleavent_sourced/finance/create_account_handler
import gleavent_sourced/facts
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit([
    "gleavent_sourced/finance/create_account_handler_test",
  ])
}

// Helper function to create test metadata
fn create_test_metadata() {
  dict.new()
}

// Helper function to persist initial events for tests
fn setup_initial_events(db, events) {
  let test_metadata = create_test_metadata()
  let assert Ok(_) =
    facts.append_events_unchecked(db, events, account_events.encode, test_metadata)
}

// Helper function to create a timestamp for testing
fn test_timestamp() {
  timestamp.from_unix_seconds(1704067200) // 2024-01-01T00:00:00.000Z
}

pub fn successful_account_creation_creates_event_test() {
  test_runner.txn(fn(db) {
    // No setup needed - account should not exist

    // Create account command
    let command =
      CreateAccountCommand("ACC-001", 1000, 500, test_timestamp())
    let handler = create_account_handler.create_account_handler(command)
    let metadata = create_test_metadata()

    // Execute command
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful account creation
    let assert CommandAccepted(events) = result
    let assert [
      AccountCreated("ACC-001", 1000, 500, _),
    ] = events
  })
}

pub fn creating_existing_account_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Account already exists
    let initial_events = [
      AccountCreated("ACC-001", 500, 300, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to create the same account again
    let command =
      CreateAccountCommand("ACC-001", 1000, 500, test_timestamp())
    let handler = create_account_handler.create_account_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Account already exists"
  })
}

pub fn empty_account_id_fails_test() {
  test_runner.txn(fn(db) {
    // No setup needed

    // Try to create account with empty account ID
    let command = CreateAccountCommand("", 1000, 500, test_timestamp())
    let handler = create_account_handler.create_account_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Account ID cannot be empty"
  })
}

pub fn negative_initial_balance_fails_test() {
  test_runner.txn(fn(db) {
    // No setup needed

    // Try to create account with negative initial balance
    let command =
      CreateAccountCommand("ACC-001", -100, 500, test_timestamp())
    let handler = create_account_handler.create_account_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Initial balance cannot be negative"
  })
}

pub fn zero_initial_balance_succeeds_test() {
  test_runner.txn(fn(db) {
    // No setup needed

    // Create account with zero initial balance (should be allowed)
    let command = CreateAccountCommand("ACC-001", 0, 500, test_timestamp())
    let handler = create_account_handler.create_account_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful account creation
    let assert CommandAccepted(events) = result
    let assert [AccountCreated("ACC-001", 0, 500, _)] = events
  })
}

pub fn zero_daily_limit_fails_test() {
  test_runner.txn(fn(db) {
    // No setup needed

    // Try to create account with zero daily limit
    let command = CreateAccountCommand("ACC-001", 1000, 0, test_timestamp())
    let handler = create_account_handler.create_account_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Daily limit must be positive"
  })
}

pub fn negative_daily_limit_fails_test() {
  test_runner.txn(fn(db) {
    // No setup needed

    // Try to create account with negative daily limit
    let command =
      CreateAccountCommand("ACC-001", 1000, -500, test_timestamp())
    let handler = create_account_handler.create_account_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Daily limit must be positive"
  })
}

pub fn large_initial_balance_and_daily_limit_succeeds_test() {
  test_runner.txn(fn(db) {
    // No setup needed

    // Create account with large values
    let command =
      CreateAccountCommand("ACC-PREMIUM", 1000000, 50000, test_timestamp())
    let handler = create_account_handler.create_account_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful account creation
    let assert CommandAccepted(events) = result
    let assert [AccountCreated("ACC-PREMIUM", 1000000, 50000, _)] = events
  })
}
