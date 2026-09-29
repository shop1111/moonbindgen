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
  if row != 100 || value != 42 || finalized != 0 || version != Some("3.53.4") {
    @abort.abort("SQLite query or cleanup failed")
  }
  let (blob_prepare, blob_statement) = sqlite3_prepare_v2(
    db,
    @utf8.encode("SELECT ?1"),
    -1,
  )
  if blob_prepare != 0 {
    @abort.abort("SQLite BLOB prepare failed")
  }
  let payload = b"\x00\x2a\x00"
  let blob_bind = sqlite3_bind_blob(blob_statement, 1, payload)
  let blob_row = sqlite3_step(blob_statement)
  let blob_value = sqlite3_column_blob(blob_statement, 0)
  if blob_bind != 0 || blob_row != 100 || blob_value != Some(payload) {
    @abort.abort("SQLite BLOB round trip failed")
  }
  let _ = sqlite3_reset(blob_statement)
  let empty_bind = sqlite3_bind_blob(blob_statement, 1, Bytes::make(0, b'\x00'))
  let empty_row = sqlite3_step(blob_statement)
  let empty_value = sqlite3_column_blob(blob_statement, 0)
  if empty_bind != 0 ||
    empty_row != 100 ||
    empty_value != Some(Bytes::make(0, b'\x00')) {
    @abort.abort("SQLite empty BLOB failed")
  }
  let _ = sqlite3_reset(blob_statement)
  let null_bind = sqlite3_bind_null(blob_statement, 1)
  let null_row = sqlite3_step(blob_statement)
  let null_value = sqlite3_column_blob(blob_statement, 0)
  let blob_finalized = sqlite3_finalize(blob_statement)
  let closed = sqlite3_close(db)
  if null_bind != 0 ||
    null_row != 100 ||
    null_value != None ||
    blob_finalized != 0 ||
    closed != 0 {
    @abort.abort("SQLite NULL BLOB or cleanup failed")
  }
  println("SELECT 42 => " + value.to_string())
  println("SQLite BLOB => 3 bytes, empty, NULL")
}
