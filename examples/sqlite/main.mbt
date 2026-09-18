///|
#borrow(filename)
extern "C" fn mb_sqlite_open(filename : Bytes) -> C_sqlite3 = "mb_sqlite_open"

///|
#borrow(sql)
extern "C" fn mb_sqlite_prepare(db : C_sqlite3, sql : Bytes) -> C_sqlite3_stmt = "mb_sqlite_prepare"

///|
extern "C" fn mb_sqlite_is_null(ptr : C_sqlite3) -> Int = "mb_sqlite_is_null"

///|
extern "C" fn mb_sqlite_stmt_is_null(ptr : C_sqlite3_stmt) -> Int = "mb_sqlite_is_null"

///|
fn main {
  let db = mb_sqlite_open(@utf8.encode(":memory:"))
  if mb_sqlite_is_null(db) != 0 {
    @abort.abort("sqlite3_open failed")
  }
  let statement = mb_sqlite_prepare(db, @utf8.encode("SELECT 42"))
  if mb_sqlite_stmt_is_null(statement) != 0 {
    let _ = sqlite3_close(db)
    @abort.abort("sqlite3_prepare_v2 failed")
  }
  let row = sqlite3_step(statement)
  let value = sqlite3_column_int(statement, 0)
  let finalized = sqlite3_finalize(statement)
  let closed = sqlite3_close(db)
  if row != 100 || value != 42 || finalized != 0 || closed != 0 {
    @abort.abort("SQLite query or cleanup failed")
  }
  println("SELECT 42 => " + value.to_string())
}
