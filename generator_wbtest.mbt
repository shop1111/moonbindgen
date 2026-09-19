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

///|
test "extracts a typed C function model" {
  let node = @json.parse(
    (
      #|{"kind":"FunctionDecl","name":"sum","mangledName":"sum","type":{"qualType":"int (int, int)"},"inner":[{"kind":"ParmVarDecl","name":"left","type":{"qualType":"int"}},{"kind":"ParmVarDecl","name":"right","type":{"qualType":"int"}}]}
    ),
  )
  guard c_function(node, { file: "fixture.h", line: 7 }) is Some(function) else {
    fail("expected a C function")
  }
  assert_eq(function.name, "sum")
  assert_eq(function.return_type, "int")
  assert_eq(function.parameters.length(), 2)
  assert_eq(function.parameters[0].name, "left")
  assert_eq(function.parameters[1].c_type, "int")
  assert_eq(function.source.line, 7)
}

///|
test "tracks explicit and inherited Clang source locations" {
  let ast = @json.parse(
    (
      #|{"inner":[{"kind":"TypedefDecl","name":"included_t","loc":{"file":"include/base.h","line":1}},{"kind":"TypedefDecl","name":"second_t","loc":{"line":2}},{"kind":"FunctionDecl","name":"run","loc":{"file":"main.h","line":4},"type":{"qualType":"int (int)"},"inner":[{"kind":"ParmVarDecl","name":"value","type":{"qualType":"int"}}]}]}
    ),
  )
  let nodes = located_nodes(ast)
  assert_eq(nodes.length(), 3)
  assert_eq(nodes[0].source.file, "include/base.h")
  assert_eq(nodes[1].source.file, "include/base.h")
  assert_eq(nodes[2].source.file, "main.h")
  assert_eq(nodes[2].source.line, 4)
}
