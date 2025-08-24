//// Conversion utilities for parrot parameters to pog values

import gleam/list
import parrot/dev
import pog

/// Convert parrot Param types to pog Value types for database queries.
/// Based on the wrapper function from parrot documentation.
pub fn parrot_to_pog(param: dev.Param) -> pog.Value {
  case param {
    dev.ParamDynamic(_) ->
      panic as "ParamDynamic not supported - use specific typed parameters instead"
    dev.ParamBool(x) -> pog.bool(x)
    dev.ParamFloat(x) -> pog.float(x)
    dev.ParamInt(x) -> pog.int(x)
    dev.ParamString(x) -> pog.text(x)
    dev.ParamBitArray(x) -> pog.bytea(x)
    dev.ParamList(x) -> pog.array(parrot_to_pog, x)
    dev.ParamTimestamp(x) -> pog.timestamp(x)
  }
}

/// Helper function to convert a list of parrot params to pog values and add them to a query
pub fn parameters(query: pog.Query(t), params: List(dev.Param)) -> pog.Query(t) {
  list.fold(params, query, fn(q, param) {
    pog.parameter(q, parrot_to_pog(param))
  })
}
