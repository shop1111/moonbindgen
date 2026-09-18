///|
test "resolves supported C types without guessing pointer ownership" {
  let aliases : Map[String, String] = Map([
    ("score_t", "int"),
    ("points_t", "score_t"),
  ])
  let opaque_types : Map[String, Bool] = Map([("widget", true)])
  let enums : Map[String, Bool] = Map([("mode", true)])
  assert_eq(
    resolve_type("points_t", aliases, opaque_types, enums, result=false),
    Some("Int"),
  )
  assert_eq(
    resolve_type("widget *", aliases, opaque_types, enums, result=false),
    Some("C_widget"),
  )
  assert_eq(
    resolve_type("enum mode", aliases, opaque_types, enums, result=false),
    Some("Int"),
  )
  assert_eq(
    resolve_type("const int", aliases, opaque_types, enums, result=false),
    Some("Int"),
  )
  assert_eq(
    resolve_type("char *", aliases, opaque_types, enums, result=false),
    None,
  )
  assert_eq(
    resolve_type("int *", aliases, opaque_types, enums, result=false),
    None,
  )
  assert_eq(
    resolve_type("long", aliases, opaque_types, enums, result=false),
    None,
  )
}

///|
test "rejects unknown Clang AST root" {
  let mut rejected = false
  try {
    let _ = generate("{\"kind\":\"Other\"}", "fixture.h")
  } catch {
    _ => rejected = true
  }
  assert_true(rejected)
}
