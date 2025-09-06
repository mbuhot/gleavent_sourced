import gleam/dict
import gleam/time/timestamp
import gleavent_sourced/command_handler.{CommandAccepted, CommandRejected}
import gleavent_sourced/finance/account_commands.{
  TransferMoneyCommand, BusinessRuleViolation,
}
import gleavent_sourced/finance/account_events.{
  AccountCreated, MoneyTransferred, MoneyWithdrawn,
}
import gleavent_sourced/finance/transfer_money_handler
import gleavent_sourced/facts
import gleavent_sourced/test_runner

pub fn main() {
  test_runner.run_eunit([
    "gleavent_sourced/finance/transfer_money_handler_test",
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

pub fn successful_transfer_creates_event_test() {
  test_runner.txn(fn(db) {
    // Setup: Create two accounts with balances and daily limits
    let initial_events = [
      AccountCreated("ACC-001", 1000, 500, test_timestamp()),
      AccountCreated("ACC-002", 500, 300, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Create transfer command
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-002",
        200,
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful transfer
    let assert CommandAccepted(events) = result
    let assert [
      MoneyTransferred("ACC-001", "ACC-002", 200, "TRANS-001", _),
    ] = events
  })
}

pub fn transfer_from_nonexistent_account_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Only create destination account
    let initial_events = [
      AccountCreated("ACC-002", 500, 300, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to transfer from non-existent source account
    let command =
      TransferMoneyCommand(
        "ACC-999",
        "ACC-002",
        100,
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Source account does not exist"
  })
}

pub fn transfer_to_nonexistent_account_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Only create source account
    let initial_events = [
      AccountCreated("ACC-001", 1000, 500, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to transfer to non-existent destination account
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-999",
        100,
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Destination account does not exist"
  })
}

pub fn transfer_with_insufficient_funds_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create accounts where source has insufficient funds
    let initial_events = [
      AccountCreated("ACC-001", 100, 500, test_timestamp()),
      AccountCreated("ACC-002", 500, 300, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to transfer more than available balance
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-002",
        200, // More than the 100 balance
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Insufficient funds"
  })
}

pub fn transfer_exceeding_daily_limit_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create accounts and make the source account hit daily limit
    let initial_events = [
      AccountCreated("ACC-001", 1000, 200, test_timestamp()), // Daily limit of 200
      AccountCreated("ACC-002", 500, 300, test_timestamp()),
      MoneyWithdrawn("ACC-001", 150, test_timestamp()), // Already spent 150 today
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to transfer 100 (total daily spending would be 250, exceeding limit of 200)
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-002",
        100,
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Transfer would exceed daily spending limit"
  })
}

pub fn negative_transfer_amount_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create two valid accounts
    let initial_events = [
      AccountCreated("ACC-001", 1000, 500, test_timestamp()),
      AccountCreated("ACC-002", 500, 300, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to transfer negative amount
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-002",
        -100, // Negative amount
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Transfer amount must be positive"
  })
}

pub fn zero_transfer_amount_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create two valid accounts
    let initial_events = [
      AccountCreated("ACC-001", 1000, 500, test_timestamp()),
      AccountCreated("ACC-002", 500, 300, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to transfer zero amount
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-002",
        0, // Zero amount
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Transfer amount must be positive"
  })
}

pub fn transfer_to_same_account_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create one account
    let initial_events = [
      AccountCreated("ACC-001", 1000, 500, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to transfer to same account
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-001", // Same account as source
        100,
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Cannot transfer to the same account"
  })
}

pub fn empty_transfer_id_fails_test() {
  test_runner.txn(fn(db) {
    // Setup: Create two valid accounts
    let initial_events = [
      AccountCreated("ACC-001", 1000, 500, test_timestamp()),
      AccountCreated("ACC-002", 500, 300, test_timestamp()),
    ]
    let _ = setup_initial_events(db, initial_events)

    // Try to transfer with empty transfer ID
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-002",
        100,
        "", // Empty transfer ID
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should be rejected
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify rejection with correct error message
    let assert CommandRejected(BusinessRuleViolation(message)) = result
    assert message == "Transfer ID cannot be empty"
  })
}

pub fn transfer_with_previous_outgoing_transfers_within_limit_succeeds_test() {
  test_runner.txn(fn(db) {
    // Setup: Create accounts and previous transfer that stays within daily limit
    let initial_events = [
      AccountCreated("ACC-001", 1000, 500, test_timestamp()), // Daily limit of 500
      AccountCreated("ACC-002", 500, 300, test_timestamp()),
      AccountCreated("ACC-003", 200, 200, test_timestamp()),
      MoneyTransferred("ACC-001", "ACC-003", 200, "TRANS-PREV", test_timestamp()), // Previous outgoing transfer
    ]
    let _ = setup_initial_events(db, initial_events)

    // Transfer 200 more (total daily spending = 400, within limit of 500)
    let command =
      TransferMoneyCommand(
        "ACC-001",
        "ACC-002",
        200,
        "TRANS-001",
        test_timestamp(),
      )
    let handler = transfer_money_handler.create_transfer_money_handler(command)
    let metadata = create_test_metadata()

    // Execute command - should succeed
    let assert Ok(result) =
      command_handler.execute(db, handler, command, metadata)

    // Verify successful transfer
    let assert CommandAccepted(events) = result
    let assert [
      MoneyTransferred("ACC-001", "ACC-002", 200, "TRANS-001", _),
    ] = events
  })
}
