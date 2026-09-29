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
  guard c_function(node, { file: "fixture.h", line: 7, }) is Some(function) else {
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
      { name: "self", c_type: "int", canonical_type: "int", },
      { name: "Value", c_type: "int", canonical_type: "int", },
      { name: "value", c_type: "int", canonical_type: "int", },
    ],
    source: { file: "fixture.h", line: 1, },
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
      { name: "path", c_type: "string_t", canonical_type: "const char *", },
    ],
    source: { file: "fixture.h", line: 1, },
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
    InvalidConfig(message) =>
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
  assert_eq(config.unsupported_policy, Error)
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
    InvalidConfig(message) => assert_true(message.contains("unknown"))
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

///|
test "emits auditable report schema v2" {
  let ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"TypedefDecl","name":"foreign_t","loc":{"file":"include/base.h","line":2},"type":{"qualType":"int"}},{"kind":"FunctionDecl","name":"sum","mangledName":"sum","loc":{"file":"fixture.h","line":7},"type":{"qualType":"int (int, int)"},"inner":[{"kind":"ParmVarDecl","name":"left","type":{"qualType":"int"}},{"kind":"ParmVarDecl","name":"right","type":{"qualType":"int"}}]}]}
  let result = generate_with_metadata(
    ast,
    "fixture.h",
    GenerateConfig::default(),
    ToolMetadata::new("clang version 23.1.1", "x86_64-pc-windows-msvc"),
  )
  assert_true(result.report.contains("moonbindgen-report-v2"))
  assert_true(result.report.contains("clang version 23.1.1"))
  assert_true(result.report.contains("x86_64-pc-windows-msvc"))
  assert_true(result.report.contains("include/base.h"))
  assert_true(result.report.contains("\"line\": 7"))
  assert_true(result.report.contains("\"reason_code\": \"generated\""))
  assert_true(result.report.contains("pub extern \\\"C\\\" fn sum"))
}

///|
test "strict policy rejects unsupported declarations" {
  let ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"FunctionDecl","name":"unsafe_name","loc":{"file":"fixture.h","line":3},"type":{"qualType":"char *(void)"}}]}
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v1","unsupported_policy":"error"}
    ),
  )
  try generate_with_config(ast, "fixture.h", config) catch {
    Failure(message) =>
      assert_true(message.contains("unsupported declarations"))
    _ => fail("expected a policy failure")
  } noraise {
    _ => fail("expected strict policy rejection")
  }
}

///|
test "rejects typedef cycles deterministically" {
  let aliases : Map[String, String] = Map([
    ("left_t", "right_t"),
    ("right_t", "left_t"),
  ])
  assert_eq(
    resolve_type("left_t", aliases, Map([]), Map([]), result=false),
    None,
  )
}

///|
test "reports renamed output collisions" {
  let ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"FunctionDecl","name":"first","loc":{"file":"fixture.h","line":1},"type":{"qualType":"int (void)"}},{"kind":"FunctionDecl","name":"second","loc":{"line":2},"type":{"qualType":"int (void)"}}]}
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v1","renames":{"first":"same","second":"same"}}
    ),
  )
  let result = generate_with_config(ast, "fixture.h", config)
  assert_eq(result.generated, 1)
  assert_eq(result.skipped, 1)
  assert_true(result.report.contains("\"reason_code\": \"name_collision\""))
}

///|
test "reports an enum that exceeds the MoonBit Int boundary" {
  let ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"EnumDecl","name":"limit","loc":{"file":"fixture.h","line":1},"inner":[{"kind":"EnumConstantDecl","name":"LIMIT_MAX","inner":[{"value":"2147483647"}]},{"kind":"EnumConstantDecl","name":"LIMIT_OVER"}]}]}
  let result = generate(ast, "fixture.h")
  assert_true(result.report.contains("enum_value_out_of_range"))
  assert_true(!result.bindings.contains("c_limit_max"))
}

///|
test "generation output is byte deterministic" {
  let ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"FunctionDecl","name":"sum","loc":{"file":"fixture.h","line":1},"type":{"qualType":"int (int, int)"},"inner":[{"kind":"ParmVarDecl","name":"left","type":{"qualType":"int"}},{"kind":"ParmVarDecl","name":"right","type":{"qualType":"int"}}]}]}
  let first = generate(ast, "fixture.h")
  let second = generate(ast, "fixture.h")
  assert_eq(first.bindings, second.bindings)
  assert_eq(first.report, second.report)
}

///|
test "generates explicit output and UTF-8 return bridges" {
  let ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"TypedefDecl","name":"handle","loc":{"file":"fixture.h","line":1},"type":{"qualType":"struct handle"}},{"kind":"FunctionDecl","name":"create","loc":{"line":2},"type":{"qualType":"int (handle **, const char **)"},"inner":[{"kind":"ParmVarDecl","name":"out","type":{"qualType":"handle **"}},{"kind":"ParmVarDecl","name":"tail","type":{"qualType":"const char **"}}]},{"kind":"FunctionDecl","name":"count","loc":{"line":3},"type":{"qualType":"int (int *)"},"inner":[{"kind":"ParmVarDecl","name":"value","type":{"qualType":"int *"}}]},{"kind":"FunctionDecl","name":"borrowed","loc":{"line":4},"type":{"qualType":"const char *(void)"}},{"kind":"FunctionDecl","name":"owned","loc":{"line":5},"type":{"qualType":"char *(void)"}},{"kind":"FunctionDecl","name":"release","loc":{"line":6},"type":{"qualType":"void (char *)"},"inner":[{"kind":"ParmVarDecl","name":"text","type":{"qualType":"char *"}}]}]}
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v1","output_params":["create.out","count.value"],"null_inputs":["create.tail"],"utf8_borrowed_returns":["borrowed"],"utf8_owned_returns":{"owned":"release"}}
    ),
  )
  let result = generate_with_config(ast, "fixture.h", config)
  assert_eq(result.generated, 4)
  assert_eq(result.skipped, 1)
  assert_true(result.bindings.contains("pub fn create() -> (Int, C_handle)"))
  assert_true(result.bindings.contains("pub fn count() -> (Int, Int)"))
  assert_true(result.bindings.contains("pub fn owned() -> String? raise"))
  assert_true(result.report.contains("\"has_shim\": true"))
  guard result.shim is Some(shim) else { fail("expected a C shim") }
  assert_true(shim.contains("create(&mbg_value, NULL)"))
  assert_true(shim.contains("release(mbg_text)"))
  let second = generate_with_config(ast, "fixture.h", config)
  assert_eq(result.bindings, second.bindings)
  assert_eq(result.report, second.report)
  assert_eq(result.shim, second.shim)
}

///|
test "rejects conflicting and unverified bridge settings" {
  try
    parse_config(
      (
        #|{"schema":"moonbindgen-config-v1","utf8_borrowed_returns":["text"],"utf8_owned_returns":{"text":"release"}}
      ),
    )
  catch {
    InvalidConfig(message) => assert_true(message.contains("conflicts"))
  } noraise {
    _ => fail("expected ownership conflict")
  }
  let ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"FunctionDecl","name":"text","loc":{"file":"fixture.h","line":1},"type":{"qualType":"char *(void)"}}]}
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v1","utf8_owned_returns":{"text":"missing_free"}}
    ),
  )
  try generate_with_config(ast, "fixture.h", config) catch {
    Failure(message) => assert_true(message.contains("release function"))
    _ => fail("expected release function rejection")
  } noraise {
    _ => fail("expected invalid bridge rejection")
  }
  let bad_release_ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"FunctionDecl","name":"text","loc":{"file":"fixture.h","line":1},"type":{"qualType":"char *(void)"}},{"kind":"FunctionDecl","name":"release","loc":{"line":2},"type":{"qualType":"int (int)"},"inner":[{"kind":"ParmVarDecl","name":"value","type":{"qualType":"int"}}]}]}
  let bad_release = parse_config(
    (
      #|{"schema":"moonbindgen-config-v1","utf8_owned_returns":{"text":"release"}}
    ),
  )
  try generate_with_config(bad_release_ast, "fixture.h", bad_release) catch {
    Failure(message) => assert_true(message.contains("invalid string release"))
    _ => fail("expected release signature rejection")
  } noraise {
    _ => fail("expected release signature rejection")
  }
  let bad_output_ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"FunctionDecl","name":"read","loc":{"file":"fixture.h","line":1},"type":{"qualType":"int (void *)"},"inner":[{"kind":"ParmVarDecl","name":"value","type":{"qualType":"void *"}}]}]}
  let bad_output = parse_config(
    (
      #|{"schema":"moonbindgen-config-v1","output_params":["read.value"]}
    ),
  )
  try generate_with_config(bad_output_ast, "fixture.h", bad_output) catch {
    Failure(message) => assert_true(message.contains("unsupported output"))
    _ => fail("expected output type rejection")
  } noraise {
    _ => fail("expected output type rejection")
  }
}

///|
test "v2 buffer configuration is positional and rejects ambiguous policies" {
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v2","buffers":[{"function":"read","pointer":0,"length":1,"direction":"in","retention":"call"}],"return_buffers":[{"function":"view","length_function":"view_size","length_args":[0]}]}
    ),
  )
  assert_eq(config.schema_version, 2)
  assert_eq(config.buffers.length(), 1)
  assert_eq(config.buffers[0].pointer, 0)
  assert_eq(config.return_buffers[0].length_function, "view_size")
  let invalid = [
    (
      #|{"schema":"moonbindgen-config-v1","buffers":[]}
    ),
    (
      #|{"schema":"moonbindgen-config-v2","buffers":[{"function":"read","pointer":0,"length":0,"direction":"in"}]}
    ),
    (
      #|{"schema":"moonbindgen-config-v2","buffers":[{"function":"read","pointer":0.5,"length":1,"direction":"in"}]}
    ),
    (
      #|{"schema":"moonbindgen-config-v2","type_overrides":{"short":"Int"}}
    ),
  ]
  for value in invalid {
    let mut rejected = false
    ignore(parse_config(value)) catch {
      InvalidConfig(_) => rejected = true
    }
    assert_true(rejected)
  }
}

///|
test "C type model distinguishes data, records, arrays, and callbacks" {
  assert_true(is_v2_byte_pointer("const void *", const_required=true))
  assert_true(is_v2_byte_pointer("unsigned char *", const_required=false))
  assert_true(!is_v2_byte_pointer("void (*)(void *)", const_required=false))
  assert_true(!is_v2_byte_pointer("const int *", const_required=true))
  assert_true(c_type_model("struct sample").record)
  assert_true(c_type_model("enum mode").enumeration)
  assert_true(c_type_model("char[8]").array)
  assert_true(c_type_model("void (*)(void *)").function_pointer)
}

///|
test "v2 named multi-output policy rejects ambiguous fields" {
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v2","multi_outputs":[{"function":"read","outputs":[{"index":1,"name":"first"},{"index":2,"name":"second"}]}]}
    ),
  )
  assert_eq(config.multi_outputs.length(), 1)
  assert_eq(config.multi_outputs[0].outputs[1].name, "second")
  let invalid = [
    (
      #|{"schema":"moonbindgen-config-v1","multi_outputs":[]}
    ),
    (
      #|{"schema":"moonbindgen-config-v2","multi_outputs":[{"function":"read","outputs":[{"index":1,"name":"same"},{"index":2,"name":"same"}]}]}
    ),
    (
      #|{"schema":"moonbindgen-config-v2","multi_outputs":[{"function":"read","outputs":[{"index":1,"name":"status"},{"index":2,"name":"other"}]}]}
    ),
  ]
  for value in invalid {
    let mut rejected = false
    ignore(parse_config(value)) catch {
      InvalidConfig(_) => rejected = true
    }
    assert_true(rejected)
  }
}

///|
test "fallible resource release stays manual in v2 report" {
  let ast =
    #|{"kind":"TranslationUnitDecl","inner":[{"kind":"TypedefDecl","name":"token","loc":{"file":"manual.h","line":1},"type":{"qualType":"struct token"}},{"kind":"FunctionDecl","name":"token_new","loc":{"line":2},"type":{"qualType":"token *(void)"}},{"kind":"FunctionDecl","name":"token_close","loc":{"line":3},"type":{"qualType":"int (token *)"},"inner":[{"kind":"ParmVarDecl","name":"value","type":{"qualType":"token *"}}]}]}
  let config = parse_config(
    (
      #|{"schema":"moonbindgen-config-v2","resources":[{"name":"token","create":"token_new","release":"token_close"}]}
    ),
  )
  let result = generate_with_config(ast, "manual.h", config)
  assert_true(result.bindings.contains("fn token_new() -> C_token"))
  assert_true(!result.bindings.contains("MbgResource_token"))
  assert_true(result.report.contains("manual_resource_management"))
}
