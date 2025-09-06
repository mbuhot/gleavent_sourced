import gleam/result

import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/finance/account_commands.{
  type CreateAccountCommand, type AccountError, BusinessRuleViolation,
}
import gleavent_sourced/finance/account_events.{type AccountEvent}
import gleavent_sourced/finance/account_facts
import gleavent_sourced/validation.{require}

// Context built from facts to validate account creation business rules
// Contains validation state for the account being created
pub type CreateAccountContext {
  CreateAccountContext(account_exists: Bool)
}

// Default context state before loading events - assumes account doesn't exist
fn initial_context() {
  CreateAccountContext(account_exists: False)
}

// Define facts needed to validate account creation
fn facts(account_id: String) {
  [
    account_facts.account_exists(account_id, fn(_ctx, account_exists) {
      CreateAccountContext(account_exists:)
    }),
  ]
}

// Creates command handler with facts to validate account before creation
// Uses strongly-typed facts system for efficient event querying
pub fn create_account_handler(
  command: CreateAccountCommand,
) -> CommandHandler(
  CreateAccountCommand,
  AccountEvent,
  CreateAccountContext,
  AccountError,
) {
  command_handler.new(
    initial_context(),
    facts(command.account_id),
    execute,
    account_events.decode,
    account_events.encode,
  )
}

// Core business logic - validates rules then creates AccountCreated event
fn execute(
  command: CreateAccountCommand,
  context: CreateAccountContext,
) -> Result(List(AccountEvent), AccountError) {
  use _ <- result.try(account_does_not_exist(context))
  use _ <- result.try(non_empty_account_id(command.account_id))
  use _ <- result.try(non_negative_initial_balance(command.initial_balance))
  use _ <- result.try(positive_daily_limit(command.daily_limit))

  Ok([
    account_events.AccountCreated(
      command.account_id,
      command.initial_balance,
      command.daily_limit,
      command.timestamp,
    ),
  ])
}

// Validates the account doesn't already exist
fn account_does_not_exist(
  context: CreateAccountContext,
) -> Result(Nil, AccountError) {
  require(
    !context.account_exists,
    BusinessRuleViolation("Account already exists"),
  )
}

// Validates the account ID is not empty
fn non_empty_account_id(account_id: String) -> Result(Nil, AccountError) {
  require(account_id != "", BusinessRuleViolation("Account ID cannot be empty"))
}

// Validates the initial balance is non-negative
fn non_negative_initial_balance(initial_balance: Int) -> Result(Nil, AccountError) {
  require(
    initial_balance >= 0,
    BusinessRuleViolation("Initial balance cannot be negative"),
  )
}

// Validates the daily limit is positive
fn positive_daily_limit(daily_limit: Int) -> Result(Nil, AccountError) {
  require(daily_limit > 0, BusinessRuleViolation("Daily limit must be positive"))
}
