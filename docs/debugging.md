# Debugging in Gleam

This document covers debugging techniques and patterns for Gleam applications, with emphasis on proper usage of debugging tools.

## Overview

Debugging in Gleam requires understanding the available tools and their proper usage patterns. Unlike some languages with rich debugging ecosystems, Gleam debugging often relies on strategic output and careful error handling.

## The `echo` Statement

### Basic Usage

The `echo` statement is Gleam's primary debugging tool. **Crucially, `echo` works with any Gleam term, not just strings.**

```gleam
// Works with any data type
echo "Hello world"
echo 42
echo [1, 2, 3]
echo #("user", 123, True)
echo MyCustomType(field: "value")
```

### Bundling Multiple Values with Tuples

Use tuples to output multiple related values together:

```gleam
// Bundle multiple values for context
echo #("user_id", user_id, "status", status)
echo #("query_result", result, "row_count", list.length(rows))
echo #("before_filter", events, "after_filter", filtered_events)
```

### Debugging Complex Data Structures

```gleam
// Debug nested structures
echo #("event", event, "decoded_payload", decoded_payload)

// Debug function inputs and outputs
pub fn process_events(events: List(Event)) -> List(ProcessedEvent) {
  echo #("process_events_input", events)
  let result = 
    events
    |> list.map(process_single_event)
  echo #("process_events_output", result)  
  result
}
```

### Echo in Pipelines

```gleam
// Debug intermediate pipeline steps
events
|> list.filter(is_ticket_event)
|> fn(filtered) { 
   echo #("after_filter", filtered)
   filtered
}
|> list.map(decode_payload)
|> fn(decoded) {
   echo #("after_decode", decoded)
   decoded  
}
```

## Error Debugging Patterns

### Pattern Matching Failures

```gleam
// Before: Opaque pattern match failure
let assert Ok(result) = risky_operation()

// Better: Debug what actually happened
case risky_operation() {
  Ok(result) -> result
  Error(err) -> {
    echo #("risky_operation_failed", err)
    panic as "risky_operation failed"
  }
}
```

### Database Query Debugging

```gleam
pub fn debug_query(sql: String, params: List(pog.Value)) -> pog.Query(a) {
  echo #("sql", sql, "params", params)
  pog.query(sql)
  |> list.fold(params, _, fn(q, param) { pog.parameter(q, param) })
}

// Usage
let query = debug_query(
  "SELECT * FROM events WHERE event_type = $1",
  [pog.text("TicketOpened")]
)
```

### JSON Decoding Failures

```gleam
pub fn debug_decode(json_str: String, decoder: decode.Decoder(a)) -> Result(a, String) {
  echo #("decoding_json", json_str)
  case json.parse(json_str, decoder) {
    Ok(result) -> {
      echo #("decode_success", result)
      Ok(result)
    }
    Error(err) -> {
      echo #("decode_error", err)
      Error("Decode failed")
    }
  }
}
```

## Test Debugging

### Test Data Inspection

```gleam
pub fn debug_test_data_test() {
  test_runner.txn(fn(db) {
    let events = create_test_events()
    echo #("created_events", events)
    
    let assert Ok(_) = store_events(db, events)
    
    let retrieved = get_events(db)
    echo #("retrieved_events", retrieved)
    
    assert list.length(retrieved) == list.length(events)
  })
}
```

### Query Result Debugging

```gleam
pub fn debug_filter_test() {
  test_runner.txn(fn(db) {
    // ... setup events ...
    
    let filter = create_filter()
    echo #("filter_json", event_filter.to_string(filter))
    
    let assert Ok(#(events, max_seq)) = event_log.query_events(db, filter, mapper)
    echo #("query_result", events, "max_sequence", max_seq)
    
    assert list.length(events) == 1
  })
}
```

## Performance Debugging

### Timing Operations

```gleam
import gleam/time

pub fn timed(operation: fn() -> a, label: String) -> a {
  let start = time.now()
  let result = operation()
  let end = time.now()
  let duration = time.difference(end, start)
  echo #("timing", label, "duration_ms", duration)
  result
}

// Usage
let events = timed(fn() {
  query_events(db, complex_filter, mapper)
}, "complex_query")
```

### Memory Usage Patterns

```gleam
// Debug list sizes to identify memory issues
pub fn debug_list_processing(large_list: List(a)) -> List(b) {
  echo #("input_size", list.length(large_list))
  
  large_list
  |> list.map(process_item)
  |> fn(processed) {
     echo #("after_processing", list.length(processed))
     processed
   }
  |> list.filter(meets_criteria) 
  |> fn(filtered) {
     echo #("after_filtering", list.length(filtered))
     filtered
   }
}
```

## State Debugging

### Connection Pool States

```gleam
pub fn debug_pool_state(pool_name: process.Name(pog.Message)) {
  let connection = pog.named_connection(pool_name)
  echo #("pool_connection", connection)
  // Use connection for debugging queries
}
```

### Process State

```gleam
pub fn debug_process_info() {
  let pid = process.self()
  echo #("current_process", pid)
  // Add other process debugging as needed
}
```

## Error Recovery Debugging

### Graceful Degradation

```gleam
pub fn robust_operation(input: Input) -> Result(Output, String) {
  case attempt_operation(input) {
    Ok(output) -> Ok(output)
    Error(err) -> {
      echo #("operation_failed", input, "error", err, "attempting_fallback")
      case fallback_operation(input) {
        Ok(fallback_output) -> {
          echo #("fallback_succeeded", fallback_output)
          Ok(fallback_output)
        }
        Error(fallback_err) -> {
          echo #("fallback_also_failed", fallback_err)
          Error("Both primary and fallback operations failed")
        }
      }
    }
  }
}
```

## Best Practices

### 1. Use Descriptive Labels
```gleam
// Good: Context-rich debugging
echo #("user_registration", "step", "validate_email", "email", email, "result", is_valid)

// Poor: Unclear context  
echo email
echo is_valid
```

### 2. Bundle Related Information
```gleam
// Good: Related data together
echo #("db_query", sql, "params", params, "row_count", list.length(results))

// Poor: Scattered information
echo sql
echo params  
echo list.length(results)
```

### 3. Include Operation Context
```gleam
// Good: Shows what operation is being debugged
echo #("event_processing", "ticket_id", ticket_id, "events_found", list.length(events))

// Poor: No context about what's being debugged
echo events
```

### 4. Clean Up Debug Statements
Remove `echo` statements before committing to production code. Consider using conditional compilation or environment variables for debug builds.

### 5. Structured Debug Output
```gleam
// Consistent structure makes logs easier to parse
echo #("module", "event_log", "function", "query_events", "status", "success", "count", count)
```

## Common Pitfalls

### 1. Don't Use `io.debug` - It Doesn't Exist
```gleam
// Wrong - this will cause compilation errors
io.debug(value)

// Correct - use echo
echo value
```

### 2. Remember Echo Works with Any Type
```gleam
// Unnecessary string conversion
echo int.to_string(count) <> " events processed"

// Simpler and more informative
echo #("events_processed", count)
```

### 3. Don't Over-Debug Hot Paths
Excessive debugging in frequently called functions can impact performance. Use judiciously and remove when no longer needed.

This debugging approach provides rich, structured output that's easy to understand and filter, making it much easier to diagnose issues in complex Gleam applications.