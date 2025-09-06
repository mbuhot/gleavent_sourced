import gleam/time/timestamp.{type Timestamp}

// Command types for account operations

pub type CreateAccountCommand {
  CreateAccountCommand(
    account_id: String,
    initial_balance: Int,
    daily_limit: Int,
    timestamp: Timestamp,
  )
}

pub type DepositMoneyCommand {
  DepositMoneyCommand(
    account_id: String,
    amount: Int,
    timestamp: Timestamp,
  )
}

pub type WithdrawMoneyCommand {
  WithdrawMoneyCommand(
    account_id: String,
    amount: Int,
    timestamp: Timestamp,
  )
}

pub type TransferMoneyCommand {
  TransferMoneyCommand(
    from_account: String,
    to_account: String,
    amount: Int,
    transfer_id: String,
    timestamp: Timestamp,
  )
}

// Error types for account operations
pub type AccountError {
  ValidationError(message: String)
  BusinessRuleViolation(message: String)
}
