import gleam/string
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float.{round, truncate}
import gleam/int
import gleam/json
import gleam/result
import gleam/time/timestamp.{type Timestamp}

pub type AccountEvent {
  AccountCreated(
    account_id: String,
    initial_balance: Int,
    daily_limit: Int,
    timestamp: Timestamp,
  )
  MoneyDeposited(account_id: String, amount: Int, timestamp: Timestamp)
  MoneyWithdrawn(account_id: String, amount: Int, timestamp: Timestamp)
  MoneyTransferred(
    from_account: String,
    to_account: String,
    amount: Int,
    transfer_id: String,
    timestamp: Timestamp,
  )
}

pub fn encode(event: AccountEvent) -> #(String, json.Json) {
  case event {
    AccountCreated(account_id, initial_balance, daily_limit, timestamp) -> {
      let payload =
        json.object([
          #("account_id", json.string(account_id)),
          #("initial_balance", json.int(initial_balance)),
          #("daily_limit", json.int(daily_limit)),
          #("timestamp", json.float(timestamp.to_unix_seconds(timestamp))),
        ])
      #("AccountCreated", payload)
    }
    MoneyDeposited(account_id, amount, timestamp) -> {
      let payload =
        json.object([
          #("account_id", json.string(account_id)),
          #("amount", json.int(amount)),
          #("timestamp", json.float(timestamp.to_unix_seconds(timestamp))),
        ])
      #("MoneyDeposited", payload)
    }
    MoneyWithdrawn(account_id, amount, timestamp) -> {
      let payload =
        json.object([
          #("account_id", json.string(account_id)),
          #("amount", json.int(amount)),
          #("timestamp", json.float(timestamp.to_unix_seconds(timestamp))),
        ])
      #("MoneyWithdrawn", payload)
    }
    MoneyTransferred(from_account, to_account, amount, transfer_id, timestamp) -> {
      let payload =
        json.object([
          #("from_account", json.string(from_account)),
          #("to_account", json.string(to_account)),
          #("amount", json.int(amount)),
          #("transfer_id", json.string(transfer_id)),
          #("timestamp", json.float(timestamp.to_unix_seconds(timestamp))),
        ])
      #("MoneyTransferred", payload)
    }
  }
}

/// Decodes Timestamp from int or float
fn timestamp_decoder() -> decode.Decoder(Timestamp) {
  decode.map(
    decode.one_of(
      decode.float,
      or: [decode.map(decode.int, fn(i) { int.to_float(i) })]
    ),
    fn(timestamp_seconds) {
      let seconds = truncate(timestamp_seconds)
      let fractional = timestamp_seconds -. int.to_float(seconds)
      let nanoseconds = round(fractional *. 1_000_000_000.0)
      timestamp.from_unix_seconds_and_nanoseconds(seconds, nanoseconds)
    }
  )
}

pub fn decode(event_type: String, payload_dynamic: Dynamic) {
  let decode_with = fn(decoder) {
    decode.run(payload_dynamic, decoder)
    |> result.map_error(fn(e) { "Failed to decode " <> event_type <> " - " <> string.inspect(e) })
  }

  case event_type {
    "AccountCreated" -> decode_with(account_created_decoder())
    "MoneyDeposited" -> decode_with(money_deposited_decoder())
    "MoneyWithdrawn" -> decode_with(money_withdrawn_decoder())
    "MoneyTransferred" -> decode_with(money_transferred_decoder())
    _ -> Error("Unknown event type: " <> event_type)
  }
}

pub fn account_created_decoder() -> decode.Decoder(AccountEvent) {
  use account_id <- decode.field("account_id", decode.string)
  use initial_balance <- decode.field("initial_balance", decode.int)
  use daily_limit <- decode.field("daily_limit", decode.int)
  use timestamp <- decode.field("timestamp", timestamp_decoder())
  decode.success(AccountCreated(account_id, initial_balance, daily_limit, timestamp))
}

pub fn money_deposited_decoder() -> decode.Decoder(AccountEvent) {
  use account_id <- decode.field("account_id", decode.string)
  use amount <- decode.field("amount", decode.int)
  use timestamp <- decode.field("timestamp", timestamp_decoder())
  decode.success(MoneyDeposited(account_id, amount, timestamp))
}

pub fn money_withdrawn_decoder() -> decode.Decoder(AccountEvent) {
  use account_id <- decode.field("account_id", decode.string)
  use amount <- decode.field("amount", decode.int)
  use timestamp <- decode.field("timestamp", timestamp_decoder())
  decode.success(MoneyWithdrawn(account_id, amount, timestamp))
}

pub fn money_transferred_decoder() -> decode.Decoder(AccountEvent) {
  use from_account <- decode.field("from_account", decode.string)
  use to_account <- decode.field("to_account", decode.string)
  use amount <- decode.field("amount", decode.int)
  use transfer_id <- decode.field("transfer_id", decode.string)
  use timestamp <- decode.field("timestamp", timestamp_decoder())
  decode.success(MoneyTransferred(from_account, to_account, amount, transfer_id, timestamp))
}
