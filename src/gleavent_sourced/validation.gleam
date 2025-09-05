// Helper to convert boolean validation to Result type
// Used to enforce business rules with descriptive error messages
pub fn require(condition: Bool, error: error) -> Result(Nil, error) {
  case condition {
    False -> Error(error)
    True -> Ok(Nil)
  }
}
