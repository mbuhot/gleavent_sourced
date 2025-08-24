import gleam/erlang/process
import gleavent_sourced/connection_pool

pub fn start(_start_type, _start_args) {
  let pool_name = process.new_name("event_log")
  connection_pool.start_supervisor(pool_name)
}

pub fn stop(_state) {
  Nil
}
