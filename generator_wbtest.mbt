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
  assert_eq(function.moon_name, "sum")
  assert_eq(function.return_type, "int")
  assert_eq(function.canonical_return_type, "int")
  assert_eq(function.parameters.length(), 2)
  assert_eq(function.parameters[0].name, "left")
  assert_eq(function.parameters[1].c_type, "int")
  assert_eq(function.parameters[1].canonical_type, "int")
  assert_eq(function.source.line, 7)
}

///|
test "normalizes MoonBit identifiers and keywords" {
  assert_eq(moonbit_value_name("sqlite3_step"), "sqlite3_step")
  assert_eq(moonbit_value_name("HTTP-Open"), "http_open")
  assert_eq(moonbit_value_name("self"), "c_self")
  assert_eq(moonbit_value_name("42value"), "c_42value")
  assert_eq(opaque_type_name("HTTP-Handle"), "C_http_handle")
}

///|
test "uses sanitized parameter names without duplicates" {
  let function : CFunction = {
    name: "RUN",
    moon_name: moonbit_value_name("RUN"),
    symbol: "RUN",
    c_signature: "int (int, int, int)",
    return_type: "int",
    canonical_return_type: "int",
    parameters: [
      { name: "self", c_type: "int", canonical_type: "int" },
      { name: "Value", c_type: "int", canonical_type: "int" },
      { name: "value", c_type: "int", canonical_type: "int" },
    ],
    source: { file: "fixture.h", line: 1 },
  }
  let (rendered, _) = render_function(
    function,
    Map([]),
    Map([]),
    Map([]),
    GenerateConfig::default(),
  )
  guard rendered is Some(code) else { fail("expected rendered function") }
  assert_true(code.contains("run("))
  assert_true(code.contains("c_self : Int"))
  assert_true(code.contains("value : Int"))
  assert_true(code.contains("value_2 : Int"))
}

///|
test "uses canonical types and explicitly borrowed UTF-8 inputs" {
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v1","utf8_inputs":["open.path"]}
    ),
  )
  let function : CFunction = {
    name: "open",
    moon_name: "open",
    symbol: "open",
    c_signature: "result_t (string_t)",
    return_type: "result_t",
    canonical_return_type: "int",
    parameters: [
      { name: "path", c_type: "string_t", canonical_type: "const char *" },
    ],
    source: { file: "fixture.h", line: 1 },
  }
  let (rendered, _) = render_function(
    function,
    Map([]),
    Map([]),
    Map([]),
    config,
  )
  guard rendered is Some(code) else { fail("expected rendered function") }
  assert_true(code.contains("#borrow(path)"))
  assert_true(code.contains("path : Bytes"))
  assert_true(code.contains(") -> Int"))
}

///|
test "rejects unsafe type override targets" {
  try
    parse_config(
      (
        #|{"schema":"moonbindgen-config-v1","type_overrides":{"size_t":"Dangerous"}}
      ),
    )
  catch {
    ConfigError::InvalidConfig(message) =>
      assert_true(message.contains("supported C ABI type"))
  } noraise {
    _ => fail("expected invalid type override")
  }
}

///|
test "parses versioned generation configuration" {
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v1","include_functions":["open"],"exclude_functions":["close"],"renames":{"open":"db_open"},"type_overrides":{"size_t":"UInt64"},"utf8_inputs":["open.path"],"unsupported_policy":"error"}
    ),
  )
  assert_true(config.include_functions.contains("open"))
  assert_true(config.exclude_functions.contains("close"))
  assert_eq(config.renamed("open"), "db_open")
  assert_eq(config.type_overrides.get("size_t"), Some("UInt64"))
  assert_true(config.utf8_inputs.contains("open.path"))
  assert_eq(config.unsupported_policy, UnsupportedPolicy::Error)
}

///|
test "rejects unknown configuration fields" {
  try
    parse_config(
      (
        #|{"schema":"moonbindgen-config-v1","unknown":true}
      ),
    )
  catch {
    ConfigError::InvalidConfig(message) =>
      assert_true(message.contains("unknown"))
  } noraise {
    _ => fail("expected invalid configuration")
  }
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
