# Gleavent Sourced

An aggregateless event sourcing framework for Gleam, inspired by [Rico Fritzsche's innovative blog series](https://ricofritzsche.me/aggregateless-event-sourcing/) on rethinking event sourcing architecture.

## Philosophy & Motivation

Traditional event sourcing approaches often create tight coupling through aggregates and streams, leading to several architectural problems:

### Problems with Aggregate-Centric Event Sourcing

- **Coupling**: Aggregates create artificial boundaries that tightly couple domain logic to event storage patterns
- **Inflexibility**: One-to-one mapping between aggregates and streams makes it extremely difficult to restructure the system after deployment
- **History Rewriting**: Changing aggregate boundaries requires complex event migration and history rewriting
- **Query Limitations**: Cross-aggregate operations become complex and often require process managers and compensating actions

### The Aggregateless Approach

This project implements an alternative approach that eliminates aggregates entirely in favor of:

- **Single Global Event Log**: All events are stored in a single, unified event stream
- **Facts as Composable Units**: Lightweight, reusable components built on top of events
- **Flexible Command Handlers**: Full control over event querying with complex joins, subqueries, and CTEs
- **Dynamic Context Building**: Facts compose to create contexts for command handlers without duplicating event interpretation logic

## Key Design Principles

### Facts Over Aggregates

Instead of aggregates, we introduce **Facts** - lightweight, composable units that:
- Extract meaningful information from events
- Can be combined to build rich contexts
- Avoid duplicating event interpretation logic across handlers
- Enable flexible querying patterns

### Command Handler Autonomy

Each command handler has complete control over:
- Which events to query and how to filter them
- Complex database operations (joins, subqueries, CTEs)
- Atomic loading of necessary context

### Event Storage

- Single `events` table following
- Event data stored as JSON with metadata
- Event versioning through decoders (graceful handling of schema evolution)
- No predetermined aggregate boundaries

## Architecture Overview

Here's a complete example showing all components of a command handler that aggregates event data:

### Command

Input to the command handler

```gleam
pub type TransferMoneyCommand {
  TransferMoneyCommand(
    from_account: String,
    to_account: String,
    amount: Int,
    transfer_id: String,
    timestamp: Timestamp,
  )
}
```

### Events

Domain events that get stored

```gleam
pub type AccountEvent {
  AccountCreated(account_id: String, initial_balance: Int, daily_limit: Int, timestamp: Timestamp)
  MoneyDeposited(account_id: String, amount: Int, timestamp: Timestamp)
  MoneyWithdrawn(account_id: String, amount: Int, timestamp: Timestamp)
  MoneyTransferred(from_account: String, to_account: String, amount: Int, transfer_id: String, timestamp: Timestamp)
}
```

### Facts

Reduce events to extract meaningful information

```gleam
pub fn account_balance(
  account_id: String,
  update_context: fn(context, Int) -> context,
) -> facts.Fact(context, AccountEvent) {
  facts.new_fact(
    sql: "SELECT * FROM events WHERE payload @> jsonb_build_object('account_id', $1::text)",
    params: [pog.text(account_id)],
    apply_events: fn(context, events) {
      let balance = list.fold(events, 0, fn(acc, event) {
        case event {
          AccountCreated(_, initial_balance, _, _) -> initial_balance
          MoneyDeposited(_, amount, _) -> acc + amount
          MoneyWithdrawn(_, amount, _) -> acc - amount
          MoneyTransferred(from_id, to_id, amount, _, _) ->
            case from_id == account_id, to_id == account_id {
              True, False -> acc - amount  // Outgoing transfer
              False, True -> acc + amount  // Incoming transfer
              _, _ -> acc
            }
        }
      })
      update_context(context, balance)
    },
  )
}

pub fn account_exists(
  account_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(context, AccountEvent) {
  facts.new_fact(
    sql: "SELECT * FROM events WHERE event_type = 'AccountCreated' AND payload @> jsonb_build_object('account_id', $1::text)",
    params: [pog.text(account_id)],
    apply_events: fn(context, events) {
      update_context(context, !list.is_empty(events))
    },
  )
}

pub fn daily_spending(
  account_id: String,
  today: Timestamp,
  update_context: fn(context, Int) -> context,
) -> facts.Fact(context, AccountEvent) {
  // NOTE: parrot can also be used to keep complex SQL in separate files
  facts.new_fact(
    sql: "SELECT * FROM events WHERE
          ((event_type = 'MoneyWithdrawn' AND payload @> jsonb_build_object('account_id', $1::text)) OR
           (event_type = 'MoneyTransferred' AND payload @> jsonb_build_object('from_account', $1::text)))
          AND date_trunc('day', to_timestamp((payload->>'timestamp')::float)) = date_trunc('day', $2::timestamptz)",
    params: [pog.text(account_id), pog.timestamp(today)],
    apply_events: fn(context, events) {
      let spending = list.fold(events, 0, fn(acc, event) {
        case event {
          MoneyWithdrawn(_, amount, _) -> acc + amount
          MoneyTransferred(from_id, _, amount, _, _) ->
            case from_id == account_id {
              True -> acc + amount  // Outgoing transfer counts as spending
              False -> acc
            }
          _ -> acc
        }
      })
      update_context(context, spending)
    },
  )
}

pub fn daily_limit(
  account_id: String,
  update_context: fn(context, Int) -> context,
) -> facts.Fact(context, AccountEvent) {
  facts.new_fact(
    sql: "SELECT * FROM events WHERE event_type = 'AccountCreated' AND payload @> jsonb_build_object('account_id', $1::text)",
    params: [pog.text(account_id)],
    apply_events: fn(context, events) {
      let limit = case events {
        [AccountCreated(_, _, daily_limit, _), ..] -> daily_limit
        _ -> 0
      }
      update_context(context, limit)
    },
  )
}
```

### Command Handler

Uses Facts to create a context, validate the command and return list of Events or an Error

```gleam
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

fn facts(from_account: String, to_account: String, today: Timestamp) {
  [
    account_exists(to_account, fn(ctx, exists) {
      TransferContext(..ctx, to_account_exists: exists)
    }),
    account_balance(from_account, fn(ctx, balance) {
      TransferContext(..ctx, from_account_balance: balance)
    }),
    account_balance(to_account, fn(ctx, balance) {
      TransferContext(..ctx, to_account_balance: balance)
    }),
    daily_limit(from_account, fn(ctx, limit) {
      TransferContext(..ctx, from_account_daily_limit: limit, from_account_exists: limit > 0)
    }),
    daily_spending(from_account, today, fn(ctx, spending) {
      TransferContext(..ctx, from_account_daily_spending: spending)
    }),
  ]
}

pub fn create_transfer_handler(command: TransferMoneyCommand) {
  command_handler.new(
    initial_context(),
    facts(command.from_account, command.to_account, command.timestamp),
    execute,
    account_events.decode,
    account_events.encode,
  )
}

fn execute(command: TransferMoneyCommand, context: TransferContext) -> Result(List(AccountEvent), AccountError) {
  use _ <- result.try(require(context.from_account_exists, "Source account does not exist"))
  use _ <- result.try(require(context.to_account_exists, "Destination account does not exist"))
  use _ <- result.try(require(context.from_account_balance >= command.amount, "Insufficient funds"))
  use _ <- result.try(require(command.amount > 0, "Transfer amount must be positive"))
  use _ <- result.try(require(
    context.from_account_daily_spending + command.amount <= context.from_account_daily_limit,
    "Transfer would exceed daily spending limit"
  ))

  Ok([
    MoneyTransferred(
      command.from_account,
      command.to_account,
      command.amount,
      command.transfer_id,
      command.timestamp,
    )
  ])
}

pub type AccountError {
  ValidationError(message: String)
  BusinessRuleViolation(message: String)
}

fn require(condition: Bool, message: String) -> Result(Nil, AccountError) {
  case condition {
    True -> Ok(Nil)
    False -> Error(BusinessRuleViolation(message))
  }
}
```

### Command Dispatch

Create `CommandHandler` instances and execute logic transactionally

```gleam
pub type AccountCommand {
  CreateAccount(CreateAccountCommand)
  DepositMoney(DepositMoneyCommand)
  WithdrawMoney(WithdrawMoneyCommand)
  TransferMoney(TransferMoneyCommand)
}

pub fn handle_account_command(
  command: AccountCommand,
  db: pog.Connection,
) -> Result(CommandResult(AccountEvent, AccountError), String) {
  let metadata = dict.from_list([#("source", "api.v3")])
  case command {
    CreateAccount(create_cmd) -> {
      let handler = create_account_handler.create_account_handler(create_cmd)
      command_handler.execute(db, handler, create_cmd, metadata)
    }
    TransferMoney(transfer_cmd) -> {
      let handler = transfer_handler.create_transfer_handler(transfer)
      command_handler.execute(db, handler, transfer_cmd, metadata)
    }
    ...
  }
```

## Development

```sh
gleam deps download  # Download dependencies
gleam build  # Build the project
gleam test  # Run the tests
```

## Technology Stack

- **Gleam**: Modern functional language for the BEAM
- **PostgreSQL**: Event storage with rich querying capabilities
- **Parrot**: PostgreSQL integration for Gleam
- **Cigogne**: Database migrations
- **Gleeunit**: Testing framework


## License

MIT License
