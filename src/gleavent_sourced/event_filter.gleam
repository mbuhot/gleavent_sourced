import gleam/json
import gleam/list
import gleam/option.{type Option}
import pog

/// Builder for creating event filters with a clean API
pub type EventFilter {
  EventFilter(filters: List(FilterCondition))
  CustomSql(sql: String, params: List(pog.Value))
}

pub fn merge(l: EventFilter, r: EventFilter) {
  case l, r {
    EventFilter(l_filters), EventFilter(r_filters) ->
      EventFilter(list.append(l_filters, r_filters))
    EventFilter(filters), CustomSql(_, _) -> EventFilter(filters)
    CustomSql(_, _), EventFilter(filters) -> EventFilter(filters)
    CustomSql(_, _), CustomSql(_, _) ->
      panic as "Cannot merge two CustomSql filters"
  }
}

/// Internal representation of a single filter condition
pub type FilterCondition {
  FilterCondition(
    event_type: String,
    filter_expr: json.Json,
    tag: Option(String),
  )
}

/// Attribute filter types for building conditions
pub type AttributeFilter {
  StringEquals(field: String, value: String)
  IntEquals(field: String, value: Int)
  BoolEquals(field: String, value: Bool)
  FieldIsNull(field: String)
}

/// Create a new empty event filter builder
pub fn new() -> EventFilter {
  EventFilter(filters: [])
}

/// Create a custom SQL event filter
pub fn custom_sql(sql: String, params: List(pog.Value)) -> EventFilter {
  CustomSql(sql: sql, params: params)
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
  case filter {
    EventFilter(filters) -> {
      let combined_condition =
        combine_attribute_filters_to_condition(event_type, attribute_filters)
      EventFilter(filters: [combined_condition, ..filters])
    }
    CustomSql(_, _) -> panic as "Cannot add conditions to CustomSql filter"
  }
}

/// Create a string equality attribute filter
pub fn attr_string(field: String, value: String) -> AttributeFilter {
  StringEquals(field: field, value: value)
}

/// Create an integer equality attribute filter
pub fn attr_int(field: String, value: Int) -> AttributeFilter {
  IntEquals(field: field, value: value)
}

/// Create a boolean equality attribute filter
pub fn attr_bool(field: String, value: Bool) -> AttributeFilter {
  BoolEquals(field: field, value: value)
}

/// Create a field is null attribute filter
pub fn attr_null(field: String) -> AttributeFilter {
  FieldIsNull(field: field)
}

/// Set a tag on all filter conditions in this EventFilter
pub fn with_tag(filter: EventFilter, tag: String) -> EventFilter {
  case filter {
    EventFilter(filters) -> {
      let tagged_filters =
        list.map(filters, fn(condition) {
          FilterCondition(
            event_type: condition.event_type,
            filter_expr: condition.filter_expr,
            tag: option.Some(tag),
          )
        })
      EventFilter(filters: tagged_filters)
    }
    CustomSql(_, _) -> panic as "Cannot tag CustomSql filter"
  }
}

/// Combine multiple AttributeFilters into a single FilterCondition with AND logic
fn combine_attribute_filters_to_condition(
  event_type: String,
  attribute_filters: List(AttributeFilter),
) -> FilterCondition {
  let filter_json =
    json.object(
      list.map(attribute_filters, fn(filter) {
        case filter {
          StringEquals(field, value) -> #(field, json.string(value))
          IntEquals(field, value) -> #(field, json.int(value))
          BoolEquals(field, value) -> #(field, json.bool(value))
          FieldIsNull(field) -> #(field, json.null())
        }
      }),
    )

  FilterCondition(
    event_type: event_type,
    filter_expr: filter_json,
    tag: option.None,
  )
}
