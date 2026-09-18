#include "sqlite3.h"
#include <moonbit.h>

MOONBIT_FFI_EXPORT sqlite3 *mb_sqlite_open(moonbit_bytes_t filename) {
  sqlite3 *db = NULL;
  if (sqlite3_open((const char *)filename, &db) != SQLITE_OK) {
    if (db != NULL) sqlite3_close(db);
    return NULL;
  }
  return db;
}

MOONBIT_FFI_EXPORT sqlite3_stmt *mb_sqlite_prepare(sqlite3 *db, moonbit_bytes_t sql) {
  sqlite3_stmt *stmt = NULL;
  if (sqlite3_prepare_v2(db, (const char *)sql, -1, &stmt, NULL) != SQLITE_OK) {
    return NULL;
  }
  return stmt;
}

MOONBIT_FFI_EXPORT int mb_sqlite_is_null(void *ptr) {
  return ptr == NULL;
}
