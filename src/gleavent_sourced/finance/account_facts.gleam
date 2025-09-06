import gleam/list
import gleam/time/timestamp.{type Timestamp}
import gleavent_sourced/facts
import gleavent_sourced/finance/account_events.{type AccountEvent}
import gleavent_sourced/parrot_pog
import gleavent_sourced/sql
import gleavent_sourced/utils
import pog



/// Current balance of an account (derived from all account events)
pub fn account_balance(
  account_id: String,
  update_context: fn(context, Int) -> context,
) -> facts.Fact(context, AccountEvent) {
  facts.new_fact(
    sql: "SELECT * FROM events WHERE payload @> jsonb_build_object('account_id', $1::text) ORDER BY sequence_number",
    params: [pog.text(account_id)],
    apply_events: utils.fold_into(update_context, 0, fn(acc, event) {
      case event {
        account_events.AccountCreated(_, initial_balance, _, _) -> initial_balance
        account_events.MoneyDeposited(_, amount, _) -> acc + amount
        account_events.MoneyWithdrawn(_, amount, _) -> acc - amount
        account_events.MoneyTransferred(from_id, to_id, amount, _, _) ->
          case from_id == account_id, to_id == account_id {
            True, False -> acc - amount  // Outgoing transfer
            False, True -> acc + amount  // Incoming transfer
            _, _ -> acc
          }
      }
    }),
  )
}

/// Whether an account exists (derived from AccountCreated events)
pub fn account_exists(
  account_id: String,
  update_context: fn(context, Bool) -> context,
) -> facts.Fact(context, AccountEvent) {
  facts.new_fact(
    sql: "SELECT * FROM events WHERE event_type = 'AccountCreated' AND payload @> jsonb_build_object('account_id', $1::text)",
    params: [pog.text(account_id)],
    apply_events: utils.fold_into(update_context, False, fn(_acc, _event) { True }),
  )
}

/// Daily spending for an account (derived from MoneyWithdrawn and outgoing MoneyTransferred events)
pub fn daily_spending(
  account_id: String,
  today: Timestamp,
  update_context: fn(context, Int) -> context,
) -> facts.Fact(context, AccountEvent) {
  let #(sql_query, params, _decoder) = sql.daily_spending(account_id, today)
  let pog_params = list.map(params, parrot_pog.parrot_to_pog)

  facts.new_fact(
    sql: sql_query,
    params: pog_params,
    apply_events: utils.fold_into(update_context, 0, fn(acc, event) {
      case event {
        account_events.MoneyWithdrawn(_, amount, _) -> acc + amount
        account_events.MoneyTransferred(from_id, _, amount, _, _) ->
          case from_id == account_id {
            True -> acc + amount  // Outgoing transfer counts as spending
            False -> acc
          }
        _ -> acc
      }
    }),
  )
}

/// Daily limit of an account (derived from AccountCreated events)
pub fn daily_limit(
  account_id: String,
  update_context: fn(context, Int) -> context,
) -> facts.Fact(context, AccountEvent) {
  facts.new_fact(
    sql: "SELECT * FROM events WHERE event_type = 'AccountCreated' AND payload @> jsonb_build_object('account_id', $1::text)",
    params: [pog.text(account_id)],
    apply_events: utils.fold_into(update_context, 0, fn(_acc, event) {
      case event {
        account_events.AccountCreated(_, _, daily_limit, _) -> daily_limit
        _ -> 0
      }
    }),
  )
}
