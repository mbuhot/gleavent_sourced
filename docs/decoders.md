# Gleam Decoders Reference

This document provides a comprehensive reference for working with JSON encoding and decoding in Gleam, specifically covering the `gleam/json` and `gleam/dynamic/decode` modules.

## Overview

Gleam uses a two-stage approach for JSON handling:
1. **Encoding**: Convert Gleam values to `Json` type using `gleam/json`
2. **Decoding**: Parse JSON strings to `Dynamic` values, then decode to typed Gleam values using `gleam/dynamic/decode`

## JSON Encoding (`gleam/json`)

### Basic Types

```gleam
import gleam/json

// Primitive types
json.string("hello")        // "hello"
json.int(42)               // 42
json.float(3.14)           // 3.14
json.bool(True)            // true
json.null()                // null
```

### Complex Types

```gleam
// Arrays
json.array([1, 2, 3], json.int)  // [1, 2, 3]

// Objects (from key-value pairs)
json.object([
  #("name", json.string("Alice")),
  #("age", json.int(30)),
  #("active", json.bool(True))
])  // {"name": "Alice", "age": 30, "active": true}

// Optional values
json.nullable(Some("value"), json.string)  // "value"
json.nullable(None, json.string)           // null

// Dictionaries
json.dict(my_dict, int.to_string, json.float)
```

### Converting to String

```gleam
let my_json = json.object([#("key", json.string("value"))])

// Convert to string
json.to_string(my_json)       // Slower but simpler
json.to_string_tree(my_json)  // Faster, returns StringTree
```

## Dynamic Decoding (`gleam/dynamic/decode`)

### The Decoder Type

```gleam
pub opaque type Decoder(t) {
  Decoder(function: fn(Dynamic) -> #(t, List(DecodeError)))
}
```

A `Decoder(t)` is a value that knows how to convert `Dynamic` data into type `t`. It returns a tuple containing:
- The decoded value (or a default/invalid value if errors occurred)
- A list of decode errors (empty list means success)

### Running Decoders

```gleam
import gleam/dynamic/decode

// Parse JSON string and decode in one step
json.parse(json_string, decode.string)  // Result(String, json.DecodeError)

// Or decode from existing Dynamic value
decode.run(dynamic_value, decode.string)  // Result(String, List(decode.DecodeError))
```

### Basic Decoders

```gleam
decode.string     // Decoder(String)
decode.int        // Decoder(Int)
decode.float      // Decoder(Float)
decode.bool       // Decoder(Bool)
decode.bit_array  // Decoder(BitArray)
decode.dynamic    // Decoder(Dynamic) - always succeeds
```

### Container Decoders

```gleam
// Lists
decode.list(decode.int)  // Decoder(List(Int))

// Optional values (handles null, None, undefined)
decode.optional(decode.string)  // Decoder(Option(String))

// Dictionaries
decode.dict(decode.string, decode.int)  // Decoder(Dict(String, Int))
```

### Field Decoders

```gleam
// Single field extraction (monadic style)
let decoder = {
  use name <- decode.field("name", decode.string)
  use age <- decode.field("age", decode.int)
  decode.success(Person(name: name, age: age))
}

// Optional field with default
let decoder = {
  use name <- decode.field("name", decode.string)
  use age <- decode.optional_field("age", 0, decode.int)
  decode.success(Person(name: name, age: age))
}

// Nested field access
let decoder = {
  use email <- decode.subfield(["user", "contact", "email"], decode.string)
  decode.success(email)
}
```

### Decoder Combinators

```gleam
// Transform decoded value
decode.map(decode.int, fn(x) { x * 2 })  // Decoder(Int) that doubles the value

// Chain decoders based on previous result
decode.then(decode.string, fn(str) {
  case str {
    "int" -> decode.int
    "float" -> decode.map(decode.float, fn(f) { float.round(f) })
    _ -> decode.failure("Expected 'int' or 'float'")
  }
})

// Try multiple decoders in sequence
decode.one_of(
  decode.int,
  or: [
    decode.map(decode.string, int.parse) |> decode.then(fn(result) {
      case result {
        Ok(i) -> decode.success(i)
        Error(_) -> decode.failure("Not a valid integer")
      }
    })
  ]
)
```

#### The one_of Function

The `one_of` function allows you to try multiple decoders in sequence until one succeeds:

```gleam
pub fn one_of(
  first: Decoder(a),
  or alternatives: List(Decoder(a)),
) -> Decoder(a)
```

- `first`: The first decoder to try
- `or`: A labeled parameter containing a list of alternative decoders to try if the first fails

Example usage:
```gleam
// Try to decode as int first, then as string-to-int
let flexible_int_decoder = decode.one_of(
  decode.int,
  or: [
    decode.then(decode.string, fn(str) {
      case int.parse(str) {
        Ok(i) -> decode.success(i)
        Error(_) -> decode.failure("Not a valid integer")
      }
    })
  ]
)

// For union types
let event_decoder = decode.one_of(
  user_created_decoder(),
  or: [
    user_updated_decoder(),
    user_deleted_decoder()
  ]
)
```

### Error Handling

```gleam
// Create a decoder that always fails
decode.failure("Custom error message")

// Create a decoder that always succeeds
decode.success(42)

// Collapse all errors into a single named error
decode.collapse_errors(my_complex_decoder, "MyType")

// Transform errors
decode.map_errors(decoder, fn(errors) {
  // Modify the error list
  errors
})
```

### Complex Decoding Patterns

#### Decoding Custom Types

```gleam
pub type Event {
  UserCreated(id: String, name: String)
  UserUpdated(id: String, field: String, value: String)
}

pub fn event_decoder() -> decode.Decoder(Event) {
  {
    use event_type <- decode.field("type", decode.string)
    case event_type {
      "user_created" -> {
        use id <- decode.field("id", decode.string)
        use name <- decode.field("name", decode.string)
        decode.success(UserCreated(id: id, name: name))
      }
      "user_updated" -> {
        use id <- decode.field("id", decode.string)
        use field <- decode.field("field", decode.string)
        use value <- decode.field("value", decode.string)
        decode.success(UserUpdated(id: id, field: field, value: value))
      }
      _ -> decode.failure("Unknown event type: " <> event_type)
    }
  }
}
```

### Handling Lists of Mixed Types

```gleam
// Decode a list where each item could be different types
let mixed_decoder = decode.one_of(
  decode.map(decode.string, StringValue),
  or: [
    decode.map(decode.int, IntValue),
    decode.map(decode.bool, BoolValue)
  ]
)

let list_decoder = decode.list(mixed_decoder)
```

#### Recursive Decoders

```gleam
pub type TreeNode {
  Leaf(value: String)
  Branch(left: TreeNode, right: TreeNode)
}

pub fn tree_decoder() -> decode.Decoder(TreeNode) {
  decode.recursive(fn(tree_decoder) {
    {
      use node_type <- decode.field("type", decode.string)
      case node_type {
        "leaf" -> {
          use value <- decode.field("value", decode.string)
          decode.success(Leaf(value))
        }
        "branch" -> {
          use left <- decode.field("left", tree_decoder)
          use right <- decode.field("right", tree_decoder)
          decode.success(Branch(left: left, right: right))
        }
        _ -> decode.failure("Expected 'leaf' or 'branch'")
      }
    }
  })
}
```

## Common Patterns

### Event Store Event Decoding

```gleam
pub type EventEnvelope {
  EventEnvelope(
    sequence_number: Int,
    event_type: String,
    payload: Dynamic,
    metadata: Dict(String, Dynamic),
    occurred_at: String
  )
}

pub fn event_envelope_decoder() -> decode.Decoder(EventEnvelope) {
  {
    use sequence_number <- decode.field("sequence_number", decode.int)
    use event_type <- decode.field("event_type", decode.string)
    use payload <- decode.field("payload", decode.dynamic)
    use metadata <- decode.field("metadata", decode.dict(decode.string, decode.dynamic))
    use occurred_at <- decode.field("occurred_at", decode.string)
    decode.success(EventEnvelope(
      sequence_number: sequence_number,
      event_type: event_type,
      payload: payload,
      metadata: metadata,
      occurred_at: occurred_at
    ))
  }
}
```

### Validating While Decoding

```gleam
pub fn positive_int_decoder() -> decode.Decoder(Int) {
  decode.then(decode.int, fn(n) {
    case n > 0 {
      True -> decode.success(n)
      False -> decode.failure("Expected positive integer, got " <> int.to_string(n))
    }
  })
}
```

## Error Types

### DecodeError Structure

```gleam
pub type DecodeError {
  DecodeError(expected: String, found: String, path: List(String))
}
```

- `expected`: What type was expected (e.g., "String", "Int")
- `found`: What type was actually found (e.g., "Float", "Null")
- `path`: The path to where the error occurred (e.g., ["user", "age"])

### JSON Parse Errors

```gleam
pub type DecodeError {
  UnexpectedEndOfInput
  UnexpectedByte(String)
  UnexpectedSequence(String)
  UnableToDecode(List(decode.DecodeError))
}
```

## Best Practices

1. **Use the monadic style** with `use` for field extraction - it's more readable
2. **Handle optional fields explicitly** with `optional_field` or `optional`
3. **Validate data while decoding** using `then` and conditional logic
5. **Use `one_of` for union types** or when multiple formats are acceptable (remember to use `first` decoder and `or:` parameter)
5. **Collapse errors** for user-facing error messages
6. **Use `recursive`** for self-referencing data structures
7. **Test decoders thoroughly** on both Erlang and JavaScript targets

## Target Platform Differences

- **Erlang**: Works with Erlang terms (tuples, atoms, etc.)
- **JavaScript**: Works with JavaScript objects, arrays, and primitives
- **Lists vs Arrays**: On JavaScript, decoders can handle both Gleam lists and JS arrays
- **Dictionaries**: Different internal representations but same decoder API

This reference should be sufficient for implementing JSON encoding/decoding throughout the event store system without needing to guess at API details.
