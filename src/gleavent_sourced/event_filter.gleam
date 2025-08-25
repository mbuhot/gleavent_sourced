import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/string

/// Builder for creating event filters with a clean API
pub type EventFilter {
  EventFilter(filters: List(FilterCondition))
}

/// Internal representation of a single filter condition
pub opaque type FilterCondition {
  FilterCondition(
    event_type: String,
    filter_expr: String,
    params: Dict(String, json.Json),
  )
}

/// Attribute filter types for building JSONPath conditions
pub type AttributeFilter {
  StringEquals(field: String, value: String)
  IntEquals(field: String, value: Int)
  IntGreaterThan(field: String, value: Int)
  IntLessThan(field: String, value: Int)
  BoolEquals(field: String, value: Bool)
  FieldIsNull(field: String)
}

/// Create a new empty event filter builder
pub fn new() -> EventFilter {
  EventFilter(filters: [])
}

/// Add a filter condition for a specific event type
///
/// Multiple AttributeFilters for the same event type are combined with AND logic.
/// Multiple for_type calls create OR conditions between different event types.
///
/// Example:
/// - `for_type("TicketOpened", [attr_string("priority", "high"), attr_string("ticket_id", "T-100")])`
///   finds events where priority="high" AND ticket_id="T-100"
/// - Multiple `for_type` calls create OR conditions between event types
pub fn for_type(
  filter: EventFilter,
  event_type: String,
  attribute_filters: List(AttributeFilter),
) -> EventFilter {
  let combined_condition =
    combine_attribute_filters_to_condition(event_type, attribute_filters)
  EventFilter(filters: [combined_condition, ..filter.filters])
}

/// Create a string equality attribute filter
pub fn attr_string(field: String, value: String) -> AttributeFilter {
  StringEquals(field: field, value: value)
}

/// Create an integer equality attribute filter
pub fn attr_int(field: String, value: Int) -> AttributeFilter {
  IntEquals(field: field, value: value)
}

/// Create an integer greater than attribute filter
pub fn attr_int_gt(field: String, value: Int) -> AttributeFilter {
  IntGreaterThan(field: field, value: value)
}

/// Create an integer less than attribute filter
pub fn attr_int_lt(field: String, value: Int) -> AttributeFilter {
  IntLessThan(field: field, value: value)
}

/// Create a boolean equality attribute filter
pub fn attr_bool(field: String, value: Bool) -> AttributeFilter {
  BoolEquals(field: field, value: value)
}

/// Create a field is null attribute filter
pub fn attr_null(field: String) -> AttributeFilter {
  FieldIsNull(field: field)
}

/// Convert the event filter to a JSON string for use with SQL queries
pub fn to_string(filter: EventFilter) -> String {
  let filter_objects =
    list.map(filter.filters, fn(condition) {
      let params_list = dict.to_list(condition.params)
      let params_json = json.object(params_list)

      json.object([
        #("event_type", json.string(condition.event_type)),
        #("filter", json.string(condition.filter_expr)),
        #("params", params_json),
      ])
    })

  filter_objects
  |> list.reverse
  |> json.array(fn(x) { x })
  |> json.to_string
}

/// Combine multiple AttributeFilters into a single FilterCondition with AND logic
fn combine_attribute_filters_to_condition(
  event_type: String,
  attribute_filters: List(AttributeFilter),
) -> FilterCondition {
  case attribute_filters {
    [] ->
      FilterCondition(
        event_type: event_type,
        filter_expr: "$ ? (true)",
        params: dict.new(),
      )
    [single_filter] -> {
      let part = attribute_filter_to_condition_part(single_filter, 0)
      FilterCondition(
        event_type: event_type,
        filter_expr: "$ ? (" <> part.expression <> ")",
        params: part.params,
      )
    }
    multiple_filters -> {
      let indexed_filters =
        list.index_map(multiple_filters, fn(filter, index) { #(filter, index) })
      let parts =
        list.map(indexed_filters, fn(pair) {
          let #(filter, index) = pair
          attribute_filter_to_condition_part(filter, index)
        })
      let expressions = list.map(parts, fn(part) { part.expression })
      let combined_expr = "$ ? (" <> string.join(expressions, " && ") <> ")"
      let combined_params =
        list.fold(parts, dict.new(), fn(acc, part) {
          dict.merge(acc, part.params)
        })
      FilterCondition(
        event_type: event_type,
        filter_expr: combined_expr,
        params: combined_params,
      )
    }
  }
}

/// Helper type for building JSONPath expressions
type FilterPart {
  FilterPart(expression: String, params: dict.Dict(String, json.Json))
}

/// Convert an AttributeFilter to a condition part with unique parameter names
fn attribute_filter_to_condition_part(
  attr_filter: AttributeFilter,
  index: Int,
) -> FilterPart {
  case attr_filter {
    StringEquals(field, value) -> {
      let param_name = field <> "_param_" <> int.to_string(index)
      FilterPart(
        expression: "$." <> field <> " == $" <> param_name,
        params: dict.from_list([#(param_name, json.string(value))]),
      )
    }
    IntEquals(field, value) -> {
      let param_name = field <> "_param_" <> int.to_string(index)
      FilterPart(
        expression: "$." <> field <> " == $" <> param_name,
        params: dict.from_list([#(param_name, json.int(value))]),
      )
    }
    IntGreaterThan(field, value) -> {
      let param_name = field <> "_param_" <> int.to_string(index)
      FilterPart(
        expression: "$." <> field <> " > $" <> param_name,
        params: dict.from_list([#(param_name, json.int(value))]),
      )
    }
    IntLessThan(field, value) -> {
      let param_name = field <> "_param_" <> int.to_string(index)
      FilterPart(
        expression: "$." <> field <> " < $" <> param_name,
        params: dict.from_list([#(param_name, json.int(value))]),
      )
    }
    BoolEquals(field, value) -> {
      let param_name = field <> "_param_" <> int.to_string(index)
      FilterPart(
        expression: "$." <> field <> " == $" <> param_name,
        params: dict.from_list([#(param_name, json.bool(value))]),
      )
    }
    FieldIsNull(field) -> {
      FilterPart(
        expression: "$." <> field <> ".type() == \"null\"",
        params: dict.new(),
      )
    }
  }
}
