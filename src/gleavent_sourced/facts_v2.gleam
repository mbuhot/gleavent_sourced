import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import pog

/// Core fact type with embedded SQL and context update function
pub type Fact(context, event_type) {
  Fact(
    id: String,
    // Unique identifier for CTE naming
    sql: String,
    // Raw SQL query with $1, $2, etc. placeholders
    params: List(pog.Value),
    // Parameters for the SQL query
    apply_events: fn(context, List(event_type)) -> context,
    // Function to process events and update context
  )
}

/// Composed SQL query with parameters
pub type ComposedQuery {
  ComposedQuery(sql: String, params: List(pog.Value))
}

/// Create a new Fact with auto-generated unique ID
pub fn new_fact(
  sql sql: String,
  params params: List(pog.Value),
  apply_events apply_events: fn(context, List(event_type)) -> context,
) -> Fact(context, event_type) {
  let id = ""
  Fact(id: id, sql: sql, params: params, apply_events: apply_events)
}

/// Compose multiple facts into a single CTE query
pub fn compose_facts(facts: List(Fact(context, event_type))) -> ComposedQuery {
  case facts {
    [] ->
      ComposedQuery(
        sql: "SELECT NULL as fact_id, sequence_number, event_type, payload, metadata, 0 as max_sequence_number FROM events WHERE false",
        params: [],
      )
    _ -> {
      // Build CTEs with parameter offset handling
      let #(cte_results, _) =
        list.fold(facts, #([], #(0, 1)), fn(acc, fact) {
          let #(results_acc, #(param_offset, fact_index)) = acc
          let adjusted_sql =
            adjust_parameter_indices(
              fact.sql,
              param_offset,
              list.length(fact.params),
            )
          let cte_name = "fact_" <> int.to_string(fact_index)
          let cte_sql =
            "SELECT '"
            <> cte_name
            <> "' as fact_id, user_query.sequence_number, user_query.event_type, user_query.payload, user_query.metadata "
            <> "FROM ("
            <> adjusted_sql
            <> ") user_query"
          let result =
            CteResult(name: cte_name, sql: cte_sql, params: fact.params)
          let next_param_offset = param_offset + list.length(fact.params)
          let next_fact_index = fact_index + 1

          #([result, ..results_acc], #(next_param_offset, next_fact_index))
        })

      let cte_results = list.reverse(cte_results)
      let all_params =
        list.flatten(list.map(cte_results, fn(result) { result.params }))

      // Build the final CTE query
      let cte_clauses =
        list.map(cte_results, fn(result) {
          result.name <> " AS (" <> result.sql <> ")"
        })
        |> string.join(", ")

      let union_clause =
        list.map(cte_results, fn(result) { "SELECT * FROM " <> result.name })
        |> string.join(" UNION ALL ")

      let final_sql =
        "WITH "
        <> cte_clauses
        <> ", all_events AS ("
        <> union_clause
        <> ")"
        <> " SELECT all_events.*, MAX(all_events.sequence_number) OVER () as max_sequence_number"
        <> " FROM all_events"
        <> " ORDER BY all_events.sequence_number"

      ComposedQuery(sql: final_sql, params: all_params)
    }
  }
}

/// Build context from query results and facts
pub fn build_context(
  facts: List(Fact(context, event_type)),
  events_by_fact: dict.Dict(String, List(event_type)),
  initial_context: context,
) -> context {
  list.index_fold(facts, initial_context, fn(context_acc, fact, index) {
    let fact_id = "fact_" <> int.to_string(index + 1)
    let fact_events = dict.get(events_by_fact, fact_id) |> result.unwrap([])
    fact.apply_events(context_acc, fact_events)
  })
}

/// Query event log using composed facts
pub fn query_event_log(
  db: pog.Connection,
  facts: List(Fact(context, event_type)),
  initial_context: context,
  event_decoder: fn(String, Dynamic) -> Result(event_type, String),
) -> Result(context, String) {
  let composed_query = compose_facts(facts)

  let select_query =
    pog.query(composed_query.sql)
    |> list.fold(composed_query.params, _, fn(query, param) {
      pog.parameter(query, param)
    })
    |> pog.returning(dynamic_query_decoder())

  case pog.execute(select_query, on: db) {
    Ok(returned) -> {
      let raw_rows = returned.rows

      // Group events by fact ID and map them
      case
        list.try_map(raw_rows, fn(row) {
          case json.parse(row.payload, decode.dynamic) {
            Ok(payload_dynamic) ->
              case event_decoder(row.event_type, payload_dynamic) {
                Ok(event) -> Ok(#(row.fact_id, event))
                Error(msg) -> Error(msg)
              }
            Error(json_error) -> Error("JSON parse error: " <> string.inspect(json_error))
          }
        })
      {
        Ok(events) -> {
          let events_by_fact =
            list.group(events, fn(pr) { pr.0 })
            |> dict.map_values(fn(_k, pairs) {
              list.map(pairs, fn(pr) { pr.1 })
            })

          let final_context =
            build_context(facts, events_by_fact, initial_context)
          Ok(final_context)
        }
        Error(msg) -> Error(msg)
      }
    }
    Error(pog_error) -> Error("Database query failed: " <> string.inspect(pog_error))
  }
}

// Helper functions for parameter adjustment in SQL composition

type CteResult {
  CteResult(name: String, sql: String, params: List(pog.Value))
}

type RawEventRow {
  RawEventRow(
    fact_id: String,
    sequence_number: Int,
    event_type: String,
    payload: String,
    metadata: String,
    max_sequence_number: Int,
  )
}

fn adjust_parameter_indices(
  sql: String,
  offset: Int,
  param_count: Int,
) -> String {
  case offset {
    0 -> sql
    _ -> {
      // Process parameters in descending order to avoid infinite loops
      // Generate list from param_count down to 1
      let param_numbers = list.range(1, param_count) |> list.reverse()
      list.fold(param_numbers, sql, fn(acc_sql, param_num) {
        let param_pattern = "$" <> int.to_string(param_num)
        case string.contains(acc_sql, param_pattern) {
          True -> {
            let new_param = "$" <> int.to_string(param_num + offset)
            string.replace(acc_sql, param_pattern, new_param)
          }
          False -> acc_sql
        }
      })
    }
  }
}

fn dynamic_query_decoder() -> decode.Decoder(RawEventRow) {
  use fact_id <- decode.field(0, decode.string)
  use sequence_number <- decode.field(1, decode.int)
  use event_type <- decode.field(2, decode.string)
  use payload <- decode.field(3, decode.string)
  use metadata <- decode.field(4, decode.string)
  use max_sequence_number <- decode.field(5, decode.int)
  decode.success(RawEventRow(
    fact_id: fact_id,
    sequence_number: sequence_number,
    event_type: event_type,
    payload: payload,
    metadata: metadata,
    max_sequence_number: max_sequence_number,
  ))
}
