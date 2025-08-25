import gleam/erlang/atom
import gleam/erlang/process
import gleam/list
import gleam/string

import gleavent_sourced/connection_pool
import pog

pub fn run_eunit(module_names: List(String)) -> Nil {
  run_eunit_verbose(module_names, verbose: False)
}

pub fn run_eunit_verbose(
  module_names: List(String),
  verbose verbose: Bool,
) -> Nil {
  let base_options = [Report(#(GleeunitProgress, [Colored(True)]))]
  let options = case verbose {
    True -> [Verbose, ..base_options]
    False -> base_options
  }
  let erlang_module_names =
    list.map(module_names, fn(name) { string.replace(name, "/", "@") })
  let module_atoms = list.map(erlang_module_names, atom.create)

  let result = run_eunit_ffi(module_atoms, options)

  let code = case result {
    Ok(_) -> 0
    Error(_) -> 1
  }
  halt(code)
}

@external(erlang, "erlang", "halt")
fn halt(a: Int) -> Nil

type ReportModuleName {
  GleeunitProgress
}

type GleeunitProgressOption {
  Colored(Bool)
}

type EunitOption {
  Verbose
  // NoTty
  Report(#(ReportModuleName, List(GleeunitProgressOption)))
}

@external(erlang, "gleeunit_ffi", "run_eunit")
fn run_eunit_ffi(a: List(atom.Atom), b: List(EunitOption)) -> Result(Nil, a)

/// Executes a test function within a database transaction that is automatically rolled back.
/// This provides test isolation using a single direct connection. Changes do not persist due to rollback.
///
/// ## Example
/// ```gleam
/// pub fn my_test() {
///   test_runner.txn(fn(db) {
///     // Your test code here
///     let assert Ok(_) = pog.execute(some_query, on: db)
///     // More test operations...
///   })
/// }
/// ```
pub fn txn(callback: fn(pog.Connection) -> Nil) -> Nil {
  // Create minimal connection pool with size 1 for test
  let pool_name = process.new_name("test_pool")
  let assert Ok(_) = connection_pool.start_supervisor(pool_name, 1)
  let db = pog.named_connection(pool_name)

  // Execute test in transaction that will be rolled back
  let assert Error(pog.TransactionRolledBack(_)) =
    pog.transaction(db, fn(conn) {
      // Execute the user callback
      callback(conn)

      // Always return Error to force rollback
      Error("Test rollback")
    })
  Nil
}
