import envoy
import gleam/dynamic/decode
import gleam/erlang/process
import gleavent_sourced/event_log
import gleavent_sourced/test_runner
import pog

pub fn main() {
  test_runner.run_eunit(["gleavent_sourced/event_log_test"])
}

pub fn database_connection_test() {
  // Create a test-specific database pool
  let pool_name = process.new_name("test_db_pool")
  let assert Ok(database_url) = envoy.get("DATABASE_URL")
  let assert Ok(config) = pog.url_config(pool_name, database_url)

  let assert Ok(_pool) =
    config
    |> pog.pool_size(1)
    |> pog.start

  let db = event_log.connect(pool_name)

  let sql_query = "SELECT 1 as test_value"

  let row_decoder = {
    use value <- decode.field(0, decode.int)
    decode.success(value)
  }

  let assert Ok(result) =
    pog.query(sql_query)
    |> pog.returning(row_decoder)
    |> pog.execute(db)

  assert [1] == result.rows
  assert 1 == result.count
}
