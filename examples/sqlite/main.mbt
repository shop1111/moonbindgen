///|
fn main raise {
  let (open_status, db) = sqlite3_open(@utf8.encode(":memory:"))
  if open_status != 0 {
    let _ = sqlite3_close(db)
    @abort.abort("sqlite3_open failed")
  }
  let (prepare_status, statement) = sqlite3_prepare_v2(
    db,
    @utf8.encode("SELECT 42"),
    -1,
  )
  if prepare_status != 0 {
    let _ = sqlite3_finalize(statement)
    let _ = sqlite3_close(db)
    @abort.abort("sqlite3_prepare_v2 failed")
  }
  let version = sqlite3_libversion()
  let row = sqlite3_step(statement)
  let value = sqlite3_column_int(statement, 0)
  let finalized = sqlite3_finalize(statement)
  let closed = sqlite3_close(db)
  if row != 100 ||
    value != 42 ||
    finalized != 0 ||
    closed != 0 ||
    version != Some("3.53.4") {
    @abort.abort("SQLite query or cleanup failed")
  }
  println("SELECT 42 => " + value.to_string())
}
