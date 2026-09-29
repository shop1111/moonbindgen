///|
fn is_byte_length(raw : String) -> Bool {
  match normalized_type(raw) {
    "int"
    | "signed int"
    | "unsigned int"
    | "long"
    | "unsigned long"
    | "long long"
    | "unsigned long long" => true
    _ => false
  }
}

///|
fn validate_companion(
  owner : CFunction,
  companion : CFunction,
  args : Array[Int],
) -> Unit raise {
  if companion.c_signature.contains("...") ||
    !is_byte_length(companion.canonical_return_type) ||
    companion.parameters.length() != args.length() {
    fail("invalid buffer length or null function: " + companion.name)
  }
  for index, source_index in args {
    if source_index >= owner.parameters.length() ||
      normalized_type(owner.parameters[source_index].canonical_type) !=
      normalized_type(companion.parameters[index].canonical_type) {
      fail("buffer companion argument mismatch: " + companion.name)
    }
  }
}

///|
fn validate_v2_buffers(
  nodes : Array[LocatedNode],
  header : String,
  config : GenerateConfig,
) -> Unit raise {
  if config.schema_version != 2 {
    return
  }
  let main : Map[String, CFunction] = Map([])
  let all : Map[String, CFunction] = Map([])
  for entry in nodes {
    if text_field(entry.node, "kind") == Some("FunctionDecl") {
      match c_function(entry.node, entry.source) {
        Some(function) => {
          all[function.name] = function
          if same_header(entry.source.file, header) {
            main[function.name] = function
          }
        }
        None => ()
      }
    }
  }
  for policy in config.buffers {
    let function = match main.get(policy.function_name) {
      Some(value) if config.allows(policy.function_name) => value
      _ => fail("unknown or filtered buffer function: " + policy.function_name)
    }
    if config.return_buffer_for(function.name) is Some(_) ||
      config.utf8_borrowed_returns.contains(function.name) ||
      config.utf8_owned_returns.contains(function.name) {
      fail("conflicting buffer return policy: " + function.name)
    }
    if policy.pointer >= function.parameters.length() ||
      policy.length >= function.parameters.length() ||
      !is_v2_byte_pointer(
        function.parameters[policy.pointer].canonical_type,
        const_required=policy.direction == "in",
      ) ||
      !is_byte_length(function.parameters[policy.length].canonical_type) {
      fail("buffer pointer or length has unsupported C type: " + function.name)
    }
    if policy.copy_parameter >= 0 {
      if policy.copy_parameter >= function.parameters.length() ||
        !is_v2_callback_pointer(
          function.parameters[policy.copy_parameter].canonical_type,
        ) {
        fail("copy token requires a callback pointer: " + function.name)
      }
    }
    for key, _ in config.output_params {
      if key.has_prefix(function.name + ".") {
        fail("buffer and scalar output policies conflict: " + function.name)
      }
    }
    if function.c_signature.contains("...") ||
      (
        normalized_type(function.canonical_return_type) != "int" &&
        normalized_type(function.canonical_return_type) != "void"
      ) {
      fail("buffer function must return int or void: " + function.name)
    }
  }
  for policy in config.return_buffers {
    let function = match main.get(policy.function_name) {
      Some(value) if config.allows(policy.function_name) => value
      _ => fail("unknown or filtered return buffer: " + policy.function_name)
    }
    if config.buffer_for(function.name) is Some(_) ||
      config.utf8_borrowed_returns.contains(function.name) ||
      config.utf8_owned_returns.contains(function.name) ||
      !is_v2_byte_pointer(function.canonical_return_type, const_required=true) {
      fail(
        "return buffer must be a borrowed const byte pointer: " + function.name,
      )
    }
    let length_function = match all.get(policy.length_function) {
      Some(value) => value
      None => fail("unknown buffer length function: " + policy.length_function)
    }
    validate_companion(function, length_function, policy.length_args)
    if policy.null_function != "" {
      let null_function = match all.get(policy.null_function) {
        Some(value) => value
        None => fail("unknown buffer null function: " + policy.null_function)
      }
      validate_companion(function, null_function, policy.length_args)
    }
  }
}

///|
fn render_v2_buffer(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  config : GenerateConfig,
) -> (String?, String?, String) {
  let buffer = config.buffer_for(function.name)
  let returned = config.return_buffer_for(function.name)
  let moon_params : Array[String] = []
  let ffi_params : Array[String] = []
  let ffi_args : Array[String] = []
  let c_params : Array[String] = []
  let c_args : Array[String] = []
  let borrowed : Array[String] = []
  for index, parameter in function.parameters {
    if buffer is Some(policy) && index == policy.pointer {
      if policy.direction == "in" {
        moon_params.push("data : Bytes")
        ffi_params.push("data : Bytes")
        ffi_args.push("data")
        c_params.push("moonbit_bytes_t p" + index.to_string())
        c_args.push("(" + parameter.c_type + ")p" + index.to_string())
        borrowed.push("data")
      } else {
        c_args.push("(" + parameter.c_type + ")mbg_bytes")
      }
    } else if buffer is Some(policy) &&
      index == policy.length &&
      policy.direction == "in" {
      c_args.push("(" + parameter.c_type + ")mbg_len")
    } else if buffer is Some(policy) && index == policy.length {
      let name = "arg" + index.to_string()
      moon_params.push(name + " : Int")
      ffi_params.push(name + " : Int")
      ffi_args.push(name)
      c_params.push("int32_t p" + index.to_string())
      c_args.push("(" + parameter.c_type + ")p" + index.to_string())
    } else if buffer is Some(policy) && index == policy.copy_parameter {
      c_args.push(policy.copy_symbol)
    } else {
      let resolved = match
        resolve_configured_type(
          parameter.c_type,
          parameter.canonical_type,
          aliases,
          opaque_types,
          enums,
          config,
          utf8_input=config.is_utf8_input(function.name, parameter.name),
          result=false,
        ) {
        Some(value) => value
        None =>
          return (None, None, "unsupported parameter type: " + parameter.c_type)
      }
      let name = "arg" + index.to_string()
      let declaration = name + " : " + resolved.moon_type
      moon_params.push(declaration)
      ffi_params.push(declaration)
      ffi_args.push(name)
      if resolved.borrowed {
        borrowed.push(name)
        c_params.push("moonbit_bytes_t p" + index.to_string())
        c_args.push("(" + parameter.c_type + ")p" + index.to_string())
      } else {
        c_params.push(parameter.c_type + " p" + index.to_string())
        c_args.push("p" + index.to_string())
      }
    }
  }
  let bridge_name = "mbg_bridge_" + function.moon_name
  let call = function.name + "(" + c_args.join(", ") + ")"
  let public_head = v2_public_head(function.moon_name, moon_params)
  let returns_int = normalized_type(function.canonical_return_type) == "int"
  if returned is Some(policy) {
    let length_args = policy.length_args.map(index => "p" + index.to_string())
    let length_call = policy.length_function +
      "(" +
      length_args.join(", ") +
      ")"
    let null_call = if policy.null_function == "" {
      "0"
    } else {
      policy.null_function +
      "(" +
      length_args.join(", ") +
      ") == " +
      policy.null_symbol
    }
    ffi_params.push("mbg_absent : FixedArray[Int]")
    ffi_args.push("mbg_absent")
    c_params.push("int32_t *mbg_absent")
    borrowed.push("mbg_absent")
    let moon = "///|\n#borrow(" +
      borrowed.join(", ") +
      ")\n" +
      v2_extern(bridge_name, ffi_params, "Bytes") +
      "\n///|\n" +
      public_head +
      " -> Bytes? raise {\n" +
      "  let mbg_absent = FixedArray::make(1, 0)\n" +
      "  let value = " +
      bridge_name +
      "(" +
      ffi_args.join(", ") +
      ")\n" +
      "  if mbg_absent[0] == 1 {\n    None\n  } else if mbg_absent[0] != 0 {\n" +
      "    fail(\"invalid returned buffer length or pointer\")\n" +
      "  } else {\n    Some(value)\n  }\n}\n"
    let c = "MOONBIT_FFI_EXPORT moonbit_bytes_t " +
      bridge_name +
      "(" +
      c_params.join(", ") +
      ") {\n" +
      "  int mbg_is_null = " +
      null_call +
      ";\n" +
      "  const void *mbg_pointer = " +
      call +
      ";\n" +
      "  long long mbg_size = (long long)" +
      length_call +
      ";\n" +
      "  if (mbg_is_null) { mbg_absent[0] = 1; return moonbit_make_bytes(0, 0); }\n" +
      "  if (mbg_size < 0 || mbg_size > INT32_MAX || (mbg_pointer == NULL && mbg_size > 0)) {\n" +
      "    mbg_absent[0] = 2; return moonbit_make_bytes(0, 0);\n" +
      "  }\n  mbg_absent[0] = 0;\n" +
      "  moonbit_bytes_t mbg_bytes = moonbit_make_bytes((int32_t)mbg_size, 0);\n" +
      "  if (mbg_size > 0) memcpy(mbg_bytes, mbg_pointer, (size_t)mbg_size);\n" +
      "  return mbg_bytes;\n}\n"
    return (Some(moon), Some(c), "")
  }
  guard buffer is Some(policy) else {
    return (None, None, "missing buffer policy")
  }
  ffi_params.push("mbg_error : FixedArray[Int]")
  ffi_args.push("mbg_error")
  c_params.push("int32_t *mbg_error")
  borrowed.push("mbg_error")
  if policy.direction == "in" {
    let return_type = if returns_int { "Int" } else { "Unit" }
    let c_return_type = if returns_int { "int32_t" } else { "void" }
    let fail_return = if returns_int { "return 0;" } else { "return;" }
    let call_line = if returns_int {
      "return " + call + ";"
    } else {
      call + ";"
    }
    let moon = "///|\n#borrow(" +
      borrowed.join(", ") +
      ")\n" +
      v2_extern(bridge_name, ffi_params, return_type) +
      "\n///|\n" +
      public_head +
      " -> " +
      return_type +
      " raise {\n" +
      "  let mbg_error = FixedArray::make(1, 0)\n" +
      "  let value = " +
      bridge_name +
      "(" +
      ffi_args.join(", ") +
      ")\n" +
      "  if mbg_error[0] != 0 {\n    fail(\"buffer length exceeds supported range\")\n  }\n" +
      "  value\n}\n"
    let c = "MOONBIT_FFI_EXPORT " +
      c_return_type +
      " " +
      bridge_name +
      "(" +
      c_params.join(", ") +
      ") {\n" +
      "  size_t mbg_len = (size_t)Moonbit_array_length(p" +
      policy.pointer.to_string() +
      ");\n" +
      "  if (mbg_len > INT32_MAX) { mbg_error[0] = 1; " +
      fail_return +
      " }\n  mbg_error[0] = 0;\n  " +
      call_line +
      "\n}\n"
    return (Some(moon), Some(c), "")
  }
  let length_name = "p" + policy.length.to_string()
  let return_type = if returns_int { "(Int, Bytes)" } else { "Bytes" }
  if returns_int {
    ffi_params.push("mbg_status : FixedArray[Int]")
    ffi_args.push("mbg_status")
    c_params.push("int32_t *mbg_status")
    borrowed.push("mbg_status")
  }
  let moon = "///|\n#borrow(" +
    borrowed.join(", ") +
    ")\n" +
    v2_extern(bridge_name, ffi_params, "Bytes") +
    "\n///|\n" +
    public_head +
    " -> " +
    return_type +
    " raise {\n" +
    "  let mbg_error = FixedArray::make(1, 0)\n" +
    (if returns_int {
      "  let mbg_status = FixedArray::make(1, 0)\n"
    } else {
      ""
    }) +
    "  let value = " +
    bridge_name +
    "(" +
    ffi_args.join(", ") +
    ")\n" +
    "  if mbg_error[0] != 0 {\n    fail(\"negative output buffer capacity\")\n  }\n" +
    (if returns_int { "  (mbg_status[0], value)\n" } else { "  value\n" }) +
    "}\n"
  let c = "MOONBIT_FFI_EXPORT moonbit_bytes_t " +
    bridge_name +
    "(" +
    c_params.join(", ") +
    ") {\n" +
    "  if (" +
    length_name +
    " < 0) { mbg_error[0] = 1; " +
    (if returns_int { "mbg_status[0] = 0; " } else { "" }) +
    "return moonbit_make_bytes(0, 0); }\n" +
    "  mbg_error[0] = 0;\n" +
    "  moonbit_bytes_t mbg_bytes = moonbit_make_bytes(" +
    length_name +
    ", 0);\n  " +
    (if returns_int { "mbg_status[0] = " } else { "" }) +
    call +
    ";\n  return mbg_bytes;\n}\n"
  (Some(moon), Some(c), "")
}
