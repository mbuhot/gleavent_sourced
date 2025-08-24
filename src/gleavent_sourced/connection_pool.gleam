import envoy
import gleam/erlang/process
import gleam/otp/static_supervisor
import gleam/result
import pog

pub fn start_supervisor(
  pool_name: process.Name(pog.Message),
) -> Result(process.Pid, String) {
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
    |> pog.pool_size(15)
    |> pog.supervised

  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.add(pool_child)
  |> static_supervisor.start
  |> result.map(fn(supervisor) { supervisor.pid })
  |> result.map_error(fn(_) { "Failed to start supervisor" })
}
