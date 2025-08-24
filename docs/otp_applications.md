# OTP Applications in Gleam

This document covers how to implement OTP (Open Telecom Platform) applications in Gleam, including proper lifecycle management and supervision patterns.

## OTP Application Structure

### Basic Application Module

```gleam
// src/your_app.gleam
import gleam/otp/static_supervisor
import gleam/result
import gleam/erlang/process

pub fn start(_start_type, _start_args) {
  // Application initialization logic
  let pool_name = process.new_name("main_pool")
  
  // Create supervision tree
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(database_pool_child)
  |> static_supervisor.add(http_server_child)
  |> static_supervisor.start
  |> result.map(fn(supervisor) { supervisor.pid })  // Must return PID
  |> result.map_error(fn(_) { "Failed to start supervisor" })
}

pub fn stop(_state) {
  // Optional cleanup logic
  Nil
}

// Optional: Keep main() for gleam run compatibility
pub fn main() {
  Nil
}
```

### gleam.toml Configuration

```toml
[erlang]
application_start_module = "your_app"
```

**Important**: 
- Use the module name without `.gleam` extension
- Module must be in `src/` directory
- Must implement both `start/2` and `stop/1` functions

## Application Callbacks

### start/2 Function

**Signature:**
```gleam
pub fn start(start_type, start_args) -> Result(process.Pid, error_type)
```

**Start Types:**
- Normal application start
- Takeover from another node
- Failover from failed node

**Critical Requirements:**
- **Must return**: `Result(process.Pid, error_type)`
- **Common mistake**: Returning tuples or complex structures
- **OTP expects**: Just the supervisor PID

**Correct Pattern:**
```gleam
static_supervisor.new(static_supervisor.OneForOne)
|> static_supervisor.start
|> result.map(fn(supervisor) { supervisor.pid })  // Extract PID only
```

**Wrong Pattern:**
```gleam
// ❌ Don't return tuples
|> result.map(fn(supervisor) { #(supervisor.pid, some_state) })

// ❌ Don't return the full supervisor
|> result.map(fn(supervisor) { supervisor })
```

### stop/1 Function

```gleam
pub fn stop(_state) {
  // Optional cleanup operations
  // Close files, network connections, etc.
  Nil
}
```

## Supervision Strategies

### OneForOne Strategy
Only restart the failed child process:

```gleam
static_supervisor.new(static_supervisor.OneForOne)
|> static_supervisor.add(database_child)
|> static_supervisor.add(cache_child)
|> static_supervisor.add(worker_child)
```

If `cache_child` fails, only `cache_child` is restarted.

### OneForAll Strategy  
Restart all children if any child fails:

```gleam
static_supervisor.new(static_supervisor.OneForAll)
|> static_supervisor.add(database_child)
|> static_supervisor.add(dependent_worker)
```

If either child fails, both are restarted.

## Child Specifications

### Adding Children

Children are added using modules that provide `supervised()` functions:

```gleam
// From pog (database connections)
let db_child = 
  pog.url_config(pool_name, database_url)
  |> pog.pool_size(15)
  |> pog.supervised

// Add to supervisor
static_supervisor.new(static_supervisor.OneForOne)
|> static_supervisor.add(db_child)
|> static_supervisor.start
```

### Custom Child Processes

For processes that don't provide `supervised()`, create specifications manually using other OTP primitives like `actor` or `task`.

## Application Lifecycle

### Startup Sequence
1. OTP runtime calls `YourApp.start(start_type, start_args)`
2. Your function creates and starts supervision tree
3. Function returns supervisor PID to OTP
4. OTP links to the supervisor process
5. Application is now running and supervised

### Shutdown Sequence  
1. OTP calls `YourApp.stop(state)` if implemented
2. OTP terminates the supervision tree
3. All child processes receive shutdown signals
4. Children terminate gracefully (or are killed after timeout)
5. Application is stopped

## Common Errors and Solutions

### "badarg" Error in Application Start

**Symptoms:**
```
{badarg,[{erlang,link,[{started,<pid>,{supervisor,<pid>}}],...
```

**Cause:** Wrong return type from `start/2`.

**Solution:** Return `supervisor.pid`, not the full supervisor structure.

### Process Name Conflicts

**Problem:** Using `process.new_name()` creates different names each time.

**Solution:** Create names once and pass them as parameters:

```gleam
pub fn start(_start_type, _start_args) {
  let pool_name = process.new_name("db_pool")
  
  use database_url <- result.try(envoy.get("DATABASE_URL"))
  use config <- result.try(pog.url_config(pool_name, database_url))
  
  // Use the same pool_name throughout
  // ...
}
```

### Missing Dependencies

Ensure required OTP dependencies are in `gleam.toml`:

```toml
gleam_otp = ">= 1.1.0 and < 2.0.0"
gleam_erlang = ">= 1.2.0 and < 2.0.0"
```

## main() vs OTP Applications

### Use main() for:
- Scripts and standalone programs
- `gleam run` compatibility  
- Simple tools and utilities
- Development/testing convenience

### Use OTP application for:
- Long-running services
- Production applications
- Systems requiring supervision
- Applications with multiple processes
- Integration with OTP ecosystem

### Hybrid Approach

You can provide both:

```gleam
// OTP application entry point
pub fn start(_start_type, _start_args) {
  // Production supervision tree
}

pub fn stop(_state) {
  Nil
}

// Script entry point  
pub fn main() {
  // Development/testing logic
  Nil
}
```

## Environment Integration

### Reading Configuration

```gleam
pub fn start(_start_type, _start_args) {
  use database_url <- result.try(
    envoy.get("DATABASE_URL")
    |> result.replace_error("DATABASE_URL not set")
  )
  
  use port <- result.try(
    envoy.get("PORT")
    |> result.then(int.parse)
    |> result.replace_error("Invalid PORT")
  )
  
  // Use configuration to build supervision tree
}
```

### Error Handling

Always provide descriptive errors:

```gleam
|> result.map_error(fn(_) { "Failed to start database connection pool" })
|> result.map_error(fn(_) { "HTTP server failed to bind to port" })
```

## Debugging OTP Applications

### Check Running Applications

In Erlang shell:
```erlang
application:which_applications().
```

### View Process Tree

```erlang
observer:start().
```

### Application Logs

Look for these patterns:
- `application: your_app started`
- `application: your_app exited: {reason}`
- `supervisor: started child {pid}`

## Best Practices

1. **Keep start/2 simple** - delegate complex logic to child processes
2. **Return only PIDs** - don't return complex data structures  
3. **Handle configuration errors** - provide clear error messages
4. **Use supervision** - don't create unsupervised processes
5. **Test components independently** - don't rely on full application in unit tests
6. **Document dependencies** - especially environment variables and process registration
7. **Plan for failures** - design supervision strategy for your use case

This covers the essential patterns for implementing robust OTP applications in Gleam.