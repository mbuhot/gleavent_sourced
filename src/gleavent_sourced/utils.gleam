import gleam/list

/// Helper function that folds over a list of events and updates context with the result
///
/// This is a common pattern in Facts where you:
/// 1. Start with an initial value (zero)
/// 2. Apply a function to fold over events
/// 3. Update the context with the final folded value
pub fn fold_into(
  update_context: fn(context, value) -> context,
  zero: value,
  apply: fn(value, event) -> value,
) {
  fn(context, events) {
    list.fold(events, zero, apply) |> update_context(context, _)
  }
}
