import gleam/result
import gleam/time/timestamp.{type Timestamp}

import gleavent_sourced/command_handler.{type CommandHandler}
import gleavent_sourced/finance/account_commands.{
  type TransferMoneyCommand, type AccountError, BusinessRuleViolation,
}
import gleavent_sourced/finance/account_events.{type AccountEvent}
import gleavent_sourced/finance/account_facts
import gleavent_sourced/validation.{require}

// Context built from facts to validate money transfer business rules
// Contains validation state for both source and destination accounts
pub type TransferContext {
  TransferContext(
    from_account_exists: Bool,
    to_account_exists: Bool,
    from_account_balance: Int,
    to_account_balance: Int,
    from_account_daily_limit: Int,
    from_account_daily_spending: Int,
  )
}

// Default context state before loading events
fn initial_context() {
  TransferContext(
    from_account_exists: False,
    to_account_exists: False,
    from_account_balance: 0,
    to_account_balance: 0,
    from_account_daily_limit: 0,
    from_account_daily_spending: 0,
  )
}

// Define facts needed to validate money transfer
fn facts(from_account: String, to_account: String, today: Timestamp) {
  [
    account_facts.account_exists(to_account, fn(ctx, exists) {
      TransferContext(..ctx, to_account_exists: exists)
    }),
    account_facts.account_balance(from_account, fn(ctx, balance) {
      TransferContext(..ctx, from_account_balance: balance)
    }),
    account_facts.daily_limit(from_account, fn(ctx, limit) {
      TransferContext(..ctx, from_account_daily_limit: limit, from_account_exists: limit > 0)
    }),
    account_facts.daily_spending(from_account, today, fn(ctx, spending) {
      TransferContext(..ctx, from_account_daily_spending: spending)
    }),
  ]
}

// Creates command handler with facts to validate accounts before transfer
// Uses strongly-typed facts system for efficient event querying
pub fn create_transfer_money_handler(
  command: TransferMoneyCommand,
) -> CommandHandler(
  TransferMoneyCommand,
  AccountEvent,
  TransferContext,
  AccountError,
) {
  command_handler.new(
    initial_context(),
    facts(command.from_account, command.to_account, command.timestamp),
    execute,
    account_events.decode,
    account_events.encode,
  )
}

// Core business logic - validates rules then creates MoneyTransferred event
fn execute(
  command: TransferMoneyCommand,
  context: TransferContext,
) -> Result(List(AccountEvent), AccountError) {
  use _ <- result.try(from_account_exists(context))
  use _ <- result.try(to_account_exists(context))
  use _ <- result.try(sufficient_funds(context, command.amount))
  use _ <- result.try(positive_amount(command.amount))
  use _ <- result.try(within_daily_limit(context, command.amount))
  use _ <- result.try(different_accounts(command.from_account, command.to_account))
  use _ <- result.try(non_empty_transfer_id(command.transfer_id))

  Ok([
    account_events.MoneyTransferred(
      command.from_account,
      command.to_account,
      command.amount,
      command.transfer_id,
      command.timestamp,
    ),
  ])
}

// Validates the source account exists before allowing transfer
fn from_account_exists(context: TransferContext) -> Result(Nil, AccountError) {
  require(context.from_account_exists, BusinessRuleViolation("Source account does not exist"))
}

// Validates the destination account exists before allowing transfer
fn to_account_exists(context: TransferContext) -> Result(Nil, AccountError) {
  require(context.to_account_exists, BusinessRuleViolation("Destination account does not exist"))
}

// Validates the source account has sufficient funds for the transfer
fn sufficient_funds(context: TransferContext, amount: Int) -> Result(Nil, AccountError) {
  require(
    context.from_account_balance >= amount,
    BusinessRuleViolation("Insufficient funds"),
  )
}

// Validates the transfer amount is positive
fn positive_amount(amount: Int) -> Result(Nil, AccountError) {
  require(amount > 0, BusinessRuleViolation("Transfer amount must be positive"))
}

// Validates the transfer doesn't exceed the daily spending limit
fn within_daily_limit(context: TransferContext, amount: Int) -> Result(Nil, AccountError) {
  require(
    context.from_account_daily_spending + amount <= context.from_account_daily_limit,
    BusinessRuleViolation("Transfer would exceed daily spending limit"),
  )
}

// Validates the source and destination accounts are different
fn different_accounts(from_account: String, to_account: String) -> Result(Nil, AccountError) {
  require(
    from_account != to_account,
    BusinessRuleViolation("Cannot transfer to the same account"),
  )
}

// Validates the transfer ID is not empty
fn non_empty_transfer_id(transfer_id: String) -> Result(Nil, AccountError) {
  require(transfer_id != "", BusinessRuleViolation("Transfer ID cannot be empty"))
}
