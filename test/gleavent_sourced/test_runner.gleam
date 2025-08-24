import gleam/erlang/atom
import gleam/list
import gleam/string

pub fn run_eunit(module_names: List(String)) -> Nil {
  run_eunit_verbose(module_names, verbose: False)
}

pub fn run_eunit_verbose(module_names: List(String), verbose verbose: Bool) -> Nil {
  let base_options = [Report(#(GleeunitProgress, [Colored(True)]))]
  let options = case verbose {
    True -> [Verbose, ..base_options]
    False -> base_options
  }
  let erlang_module_names = list.map(module_names, fn(name) {
    string.replace(name, "/", "@")
  })
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
