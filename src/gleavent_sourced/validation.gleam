import gleam/result

// Helper to convert boolean validation to Result type
// Used to enforce business rules with descriptive error messages
pub fn require(condition: Bool, error: error) -> Result(Nil, error) {
  case condition {
    False -> Error(error)
    True -> Ok(Nil)
  }
}

// Higher-order function to chain validations using result.try pattern
// Enables fluent validation style: use _ <- validate(validator, value)
pub fn validate(validator, value, cont) {
  result.try(validator(value), cont)
}
