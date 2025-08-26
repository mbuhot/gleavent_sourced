# Gleam Language Patterns

## Single-Constructor Types

**DON'T** use case expressions for single-constructor types:
```gleam
// Bad
case command {
  OpenTicketCommand(ticket_id, title, description, priority) -> {
    validate_ticket(ticket_id, title, description, priority)
  }
}
```

**DO** use direct field access:
```gleam
// Good
validate_ticket(command.ticket_id, command.title, command.description, command.priority)
```

## Type Annotations for Field Access

Anonymous functions need type annotations for field access to work:

```gleam
// Bad - compiler can't infer type
event_filter: fn(command) {
  command.ticket_id  // Error: Unknown type for record access
}

// Good - explicit type annotation
event_filter: fn(command: OpenTicketCommand) {
  command.ticket_id  // Works!
}
```

## Error Handling with `use` Syntax

**DON'T** nest case expressions for error handling:
```gleam
// Bad
case validate_id(id) {
  Error(err) -> Error(err)
  Ok(_) -> case validate_title(title) {
    Error(err) -> Error(err)
    Ok(_) -> Ok(create_event())
  }
}
```

**DO** use `use` syntax:
```gleam
// Good
use _ <- result.try(validate_id(id))
use _ <- result.try(validate_title(title))
Ok(create_event())
```

## Import Patterns

Only import what you actually use:
```gleam
// Bad - importing unused constructor
import my_module.{type MyType, MyType, some_function}

// Good - only import what's used
import my_module.{type MyType, some_function}
```

## Pattern Matching vs Field Access

Use pattern matching when:
- Multiple constructors in union type
- Need to destructure multiple values at once
- Conditional logic based on constructor

Use field access when:
- Single constructor type
- Only need specific fields
- Simple value extraction

## Anonymous Functions vs Named Functions

Extract anonymous functions to module level for:
- **Testability** - can test functions independently
- **Readability** - clearer separation of concerns  
- **Reusability** - functions can be used elsewhere

```gleam
// Instead of
CommandHandler(
  event_filter: fn(cmd) { /* complex logic */ },
  command_logic: fn(cmd, ctx) { /* complex logic */ },
  // ...
)

// Do this
CommandHandler(
  event_filter: event_filter_for_command,
  command_logic: command_logic_for_command,
  // ...
)
```

## Common Gotchas

1. **Unused imports** - Gleam warns about unused imports, clean them up regularly
2. **Type inference** - Add type annotations when compiler can't infer types
3. **Case expressions** - Don't use for single-constructor types
4. **Record updates** - Use `..record` syntax for updating records
5. **Result chaining** - Use `use` syntax instead of nested case expressions