import gleam/dict.{type Dict}
import gleam/json
import gleam/list

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
pub fn for_type(
  filter: EventFilter,
  event_type: String,
  attribute_filter: AttributeFilter,
) -> EventFilter {
  let condition = attribute_filter_to_condition(event_type, attribute_filter)
  EventFilter(filters: [condition, ..filter.filters])
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

/// Convert an AttributeFilter to a FilterCondition
fn attribute_filter_to_condition(
  event_type: String,
  attr_filter: AttributeFilter,
) -> FilterCondition {
  case attr_filter {
    StringEquals(field, value) -> {
      let param_name = field <> "_param"
      FilterCondition(
        event_type: event_type,
        filter_expr: "$." <> field <> " ? (@ == $" <> param_name <> ")",
        params: dict.from_list([#(param_name, json.string(value))]),
      )
    }

    IntEquals(field, value) -> {
      let param_name = field <> "_param"
      FilterCondition(
        event_type: event_type,
        filter_expr: "$." <> field <> " ? (@ == $" <> param_name <> ")",
        params: dict.from_list([#(param_name, json.int(value))]),
      )
    }

    IntGreaterThan(field, value) -> {
      let param_name = field <> "_param"
      FilterCondition(
        event_type: event_type,
        filter_expr: "$." <> field <> " ? (@ > $" <> param_name <> ")",
        params: dict.from_list([#(param_name, json.int(value))]),
      )
    }

    IntLessThan(field, value) -> {
      let param_name = field <> "_param"
      FilterCondition(
        event_type: event_type,
        filter_expr: "$." <> field <> " ? (@ < $" <> param_name <> ")",
        params: dict.from_list([#(param_name, json.int(value))]),
      )
    }

    BoolEquals(field, value) -> {
      let param_name = field <> "_param"
      FilterCondition(
        event_type: event_type,
        filter_expr: "$." <> field <> " ? (@ == $" <> param_name <> ")",
        params: dict.from_list([#(param_name, json.bool(value))]),
      )
    }

    FieldIsNull(field) -> {
      FilterCondition(
        event_type: event_type,
        filter_expr: "$." <> field <> " ? (@.type() == \"null\")",
        params: dict.new(),
      )
    }
  }
}
