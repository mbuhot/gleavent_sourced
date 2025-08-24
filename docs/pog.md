# Pog PostgreSQL Library Guide

This document covers how to effectively use the `pog` library for PostgreSQL connections in Gleam applications.

## Basic Setup

### Dependencies

```toml
pog = ">= 4.0.0 and < 5.0.0"
gleam_erlang = ">= 1.2.0 and < 2.0.0"  # Required by pog
envoy = ">= 1.0.0 and < 2.0.0"         # For environment variables
```

### Environment Configuration

Set the database URL:
```bash
DATABASE_URL="postgres://username:password@host:port/database"
```

## Connection Patterns

### Production: Supervised Connection Pools

Use supervised pools in OTP applications:

```gleam
import gleam/erlang/process
import gleam/otp/static_supervisor
import pog

pub fn start_database_pool(pool_name: process.Name(pog.Message)) -> Result(process.Pid, String) {
  use database_url <- result.try(
    envoy.get("DATABASE_URL")
    |> result.replace_error("DATABASE_URL environment variable not set"),
  )

  use config <- result.try(
    pog.url_config(pool_name, database_url)
    |> result.replace_error("Invalid database URL"),
  )

  let pool_child =
    config
    |> pog.pool_size(15)        // Adjust based on load
    |> pog.queue_target(50)     // Queue management
    |> pog.queue_interval(1000) // Queue check interval
    |> pog.supervised           // Returns ChildSpecification

  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(pool_child)
  |> static_supervisor.start
  |> result.map(fn(supervisor) { supervisor.pid })
  |> result.map_error(fn(_) { "Failed to start supervisor" })
}

// Get connection from named pool
pub fn get_connection(pool_name: process.Name(pog.Message)) -> pog.Connection {
  pog.named_connection(pool_name)
}
```

### Testing: Direct Pool Creation

For tests, create pools directly:

```gleam
pub fn create_test_connection() -> pog.Connection {
  let pool_name = process.new_name("test_pool")
  let assert Ok(database_url) = envoy.get("DATABASE_URL")
  let assert Ok(config) = pog.url_config(pool_name, database_url)
  
  let assert Ok(_) = 
    config
    |> pog.pool_size(2)  // Small pool for tests
    |> pog.start
    
  pog.named_connection(pool_name)
}
```

## Query Execution

### Basic Query Pattern

```gleam
import gleam/dynamic/decode

// Define decoder for result rows
let user_decoder = {
  use id <- decode.field(0, decode.int)
  use name <- decode.field(1, decode.string)
  use email <- decode.field(2, decode.string)
  decode.success(User(id: id, name: name, email: email))
}

// Execute query
let query = "SELECT id, name, email FROM users WHERE active = $1"
let result = 
  pog.query(query)
  |> pog.parameter(pog.bool(True))
  |> pog.returning(user_decoder)
  |> pog.execute(on: db)

case result {
  Ok(returned) -> {
    let rows: List(User) = returned.rows
    let count: Int = returned.count
    // Process results...
  }
  Error(pog.QueryError(message, _code)) -> {
    // Handle query error
  }
}
```

### Parameter Types

Use appropriate parameter functions for different types:

```gleam
pog.query("INSERT INTO events (type, payload, count, active, data, timestamp) VALUES ($1, $2, $3, $4, $5, $6)")
|> pog.parameter(pog.text("event_type"))           // String
|> pog.parameter(pog.text(json.to_string(payload))) // JSON as string
|> pog.parameter(pog.int(42))                       // Integer
|> pog.parameter(pog.bool(True))                    // Boolean  
|> pog.parameter(pog.bytea(binary_data))           // Binary data
|> pog.parameter(pog.timestamp(now))               // Timestamp
|> pog.execute(on: db)
```

### Nullable Parameters

Handle optional values with `pog.nullable`:

```gleam
pog.query("UPDATE users SET email = $1 WHERE id = $2")
|> pog.parameter(pog.nullable(email_option, pog.text))  // Option(String)
|> pog.parameter(pog.int(user_id))
|> pog.execute(on: db)
```

### Arrays

Use `pog.array` for PostgreSQL arrays:

```gleam
let tags = ["gleam", "postgresql", "database"]
pog.query("SELECT * FROM posts WHERE tags && $1")
|> pog.parameter(pog.array(tags, pog.text))
|> pog.returning(post_decoder)
|> pog.execute(on: db)
```

## Result Handling

### The Returned Type

```gleam
pub type Returned(t) {
  Returned(count: Int, rows: List(t))
}
```

- `count`: Number of rows affected/returned
- `rows`: Decoded result rows

### Error Types

```gleam
pub type QueryError {
  QueryError(message: String, code: String)
}
```

Common error codes:
- `"23505"`: Unique constraint violation
- `"23503"`: Foreign key constraint violation  
- `"42P01"`: Relation does not exist
- `"42703"`: Column does not exist

## Transactions

### Basic Transactions

```gleam
let transaction_result = pog.transaction(db, fn(tx) {
  // All operations use 'tx' instead of 'db'
  use _result1 <- result.try(
    pog.query("INSERT INTO users (name) VALUES ($1)")
    |> pog.parameter(pog.text("Alice"))
    |> pog.execute(on: tx)
  )
  
  use result2 <- result.try(
    pog.query("INSERT INTO profiles (user_id, bio) VALUES ($1, $2)")
    |> pog.parameter(pog.int(user_id))
    |> pog.parameter(pog.text("Software engineer"))
    |> pog.execute(on: tx)
  )
  
  Ok(result2)
})

case transaction_result {
  Ok(result) -> // Transaction committed
  Error(error) -> // Transaction rolled back
}
```

## JSON Handling

### Storing JSON (JSONB)

PostgreSQL JSONB columns accept JSON as text:

```gleam
let event_data = json.object([
  #("user_id", json.int(123)),
  #("action", json.string("login"))
])

pog.query("INSERT INTO events (data) VALUES ($1)")
|> pog.parameter(pog.text(json.to_string(event_data)))
|> pog.execute(on: db)
```

### Reading JSON (JSONB)

PostgreSQL returns JSONB as text strings:

```gleam
let event_decoder = {
  use data_string <- decode.field(0, decode.string)
  // Parse the JSON string
  use data <- decode.try(json.parse(data_string, decode.dynamic))
  decode.success(Event(data: data))
}

pog.query("SELECT data FROM events WHERE id = $1")
|> pog.parameter(pog.int(event_id))
|> pog.returning(event_decoder)
|> pog.execute(on: db)
```

## Configuration Options

### Pool Configuration

```gleam
config
|> pog.host("localhost")              // Default: "127.0.0.1"
|> pog.port(5432)                     // Default: 5432
|> pog.database("myapp")              // Database name
|> pog.user("postgres")               // Username
|> pog.password(Some("secret"))       // Password (Option(String))
|> pog.pool_size(20)                  // Default: 1
|> pog.queue_target(100)              // Default: 50
|> pog.queue_interval(1000)           // Default: 1000ms
|> pog.idle_interval(60_000)          // Default: 60000ms (1 minute)
|> pog.trace(True)                    // Enable query logging
```

### SSL Configuration

```gleam
config
|> pog.ssl(pog.Prefer)  // Options: Disable, Allow, Prefer, Require
```

### Custom Connection Parameters

```gleam
config
|> pog.connection_parameter("application_name", "my_gleam_app")
|> pog.connection_parameter("statement_timeout", "30s")
```

## Common Patterns

### Count Queries

```gleam
let count_decoder = {
  use count <- decode.field(0, decode.int)
  decode.success(count)
}

let assert Ok(result) = 
  pog.query("SELECT COUNT(*) FROM users")
  |> pog.returning(count_decoder)
  |> pog.execute(on: db)

let user_count = case result.rows {
  [count] -> count
  _ -> 0
}
```

### Existence Checks

```gleam
let exists_decoder = {
  use exists <- decode.field(0, decode.bool)
  decode.success(exists)
}

let assert Ok(result) = 
  pog.query("SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)")
  |> pog.parameter(pog.text(email))
  |> pog.returning(exists_decoder)
  |> pog.execute(on: db)

let user_exists = case result.rows {
  [exists] -> exists
  _ -> False
}
```

### Batch Operations

```gleam
// Use transactions for multiple related operations
pog.transaction(db, fn(tx) {
  list.try_fold(users, Nil, fn(_, user) {
    pog.query("INSERT INTO users (name, email) VALUES ($1, $2)")
    |> pog.parameter(pog.text(user.name))
    |> pog.parameter(pog.text(user.email))
    |> pog.execute(on: tx)
    |> result.replace(Nil)
  })
})
```

## Debugging and Monitoring

### Enable Query Logging

```gleam
config |> pog.trace(True)  // Logs all SQL queries
```

### Check Pool Status

Monitor pool health in production:
- Watch for connection exhaustion errors
- Monitor query execution times
- Track connection pool utilization

### Common Connection Issues

**"noproc" errors**: Pool not started or wrong pool name
**"timeout" errors**: Pool exhausted or slow queries
**Connection refused**: Database not running or wrong connection details

## Best Practices

1. **Use supervised pools** in production applications
2. **Create test-specific pools** for testing 
3. **Handle connection errors gracefully** with proper error types
4. **Use transactions** for operations that must succeed together
5. **Configure appropriate timeouts** for your use case
6. **Monitor pool usage** in production
7. **Use prepared statement patterns** by reusing query structures
8. **Handle JSONB as strings** - PostgreSQL protocol expects text

This covers the essential patterns for using pog effectively in Gleam applications.