///|
fn v2_abi_kind(raw : String, canonical : String) -> String {
  let named = normalized_type(raw)
  if named == "size_t" {
    return "size"
  }
  if named == "ptrdiff_t" {
    return "ptrdiff"
  }
  match normalized_type(canonical) {
    "short" | "short int" | "signed short" | "signed short int" => "short"
    "unsigned short" | "unsigned short int" => "ushort"
    "long" | "long int" | "signed long" | "signed long int" => "long"
    "unsigned long" | "unsigned long int" => "ulong"
    "_Bool" | "bool" => "bool"
    _ => ""
  }
}

///|
fn v2_abi_moon_type(kind : String) -> String {
  match kind {
    "short" => "Int"
    "ushort" => "UInt"
    "long" | "ptrdiff" => "Int64"
    "ulong" | "size" => "UInt64"
    "bool" => "Bool"
    _ => ""
  }
}

///|
fn v2_abi_c_type(kind : String) -> String {
  match kind {
    "short" | "bool" => "int32_t"
    "ushort" => "uint32_t"
    "long" | "ptrdiff" => "int64_t"
    "ulong" | "size" => "uint64_t"
    _ => ""
  }
}

///|
fn v2_abi_range_check(kind : String, value : String) -> String {
  match kind {
    "short" => value + " < SHRT_MIN || " + value + " > SHRT_MAX"
    "ushort" => value + " > USHRT_MAX"
    "long" => value + " < LONG_MIN || " + value + " > LONG_MAX"
    "ulong" => value + " > ULONG_MAX"
    "size" => value + " > SIZE_MAX"
    "ptrdiff" => value + " < PTRDIFF_MIN || " + value + " > PTRDIFF_MAX"
    _ => ""
  }
}

///|
fn needs_v2_abi_bridge(function : CFunction, config : GenerateConfig) -> Bool {
  if config.schema_version != 2 {
    return false
  }
  if v2_abi_kind(function.return_type, function.canonical_return_type) != "" {
    return true
  }
  for parameter in function.parameters {
    if v2_abi_kind(parameter.c_type, parameter.canonical_type) != "" {
      return true
    }
  }
  false
}

///|
fn render_v2_abi_bridge(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  config : GenerateConfig,
) -> (String?, String?, String) {
  if function.c_signature.contains("...") {
    return (None, None, "variadic function")
  }
  let return_kind = v2_abi_kind(
    function.return_type,
    function.canonical_return_type,
  )
  let moon_return = if return_kind != "" {
    v2_abi_moon_type(return_kind)
  } else {
    match
      resolve_configured_type(
        function.return_type,
        function.canonical_return_type,
        aliases,
        opaque_types,
        enums,
        config,
        utf8_input=false,
        result=true,
      ) {
      Some(value) => value.moon_type
      None =>
        return (None, None, "unsupported return type: " + function.return_type)
    }
  }
  let c_return = if return_kind != "" {
    v2_abi_c_type(return_kind)
  } else {
    function.return_type
  }
  let moon_params : Array[String] = []
  let ffi_params : Array[String] = []
  let ffi_args : Array[String] = []
  let c_params : Array[String] = []
  let c_args : Array[String] = []
  let borrowed : Array[String] = []
  let guards : Array[String] = []
  for index, parameter in function.parameters {
    let kind = v2_abi_kind(parameter.c_type, parameter.canonical_type)
    let moon_type = if kind != "" {
      v2_abi_moon_type(kind)
    } else {
      match
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
        Some(value) => value.moon_type
        None =>
          return (None, None, "unsupported parameter type: " + parameter.c_type)
      }
    }
    let name = "arg" + index.to_string()
    moon_params.push(name + " : " + moon_type)
    ffi_params.push(name + " : " + moon_type)
    ffi_args.push(name)
    let c_name = "p" + index.to_string()
    if kind != "" {
      c_params.push(v2_abi_c_type(kind) + " " + c_name)
      c_args.push("(" + parameter.c_type + ")" + c_name)
      let check = v2_abi_range_check(kind, c_name)
      if check != "" {
        guards.push(check)
      }
    } else if moon_type == "Bytes" {
      borrowed.push(name)
      c_params.push("moonbit_bytes_t " + c_name)
      c_args.push("(" + parameter.c_type + ")" + c_name)
    } else {
      c_params.push(parameter.c_type + " " + c_name)
      c_args.push(c_name)
    }
  }
  let bridge_name = "mbg_bridge_" + function.moon_name
  ffi_params.push("mbg_error : FixedArray[Int]")
  ffi_args.push("mbg_error")
  c_params.push("int32_t *mbg_error")
  borrowed.push("mbg_error")
  let moon = "///|\n#borrow(" +
    borrowed.join(", ") +
    ")\n" +
    v2_extern(bridge_name, ffi_params, moon_return) +
    "\n///|\n" +
    v2_public_head(function.moon_name, moon_params) +
    " -> " +
    moon_return +
    " raise {\n" +
    "  let mbg_error = FixedArray::make(1, 0)\n" +
    "  let value = " +
    bridge_name +
    "(" +
    ffi_args.join(", ") +
    ")\n" +
    "  if mbg_error[0] != 0 {\n    fail(\"C scalar argument is out of range\")\n  }\n" +
    "  value\n}\n"
  let failure_return = match moon_return {
    "Unit" => "return;"
    "Float" | "Double" => "return 0.0;"
    _ => "return 0;"
  }
  let call = function.name + "(" + c_args.join(", ") + ")"
  let call_line = if moon_return == "Unit" {
    call + ";"
  } else {
    "return (" + c_return + ")" + call + ";"
  }
  let c = "MOONBIT_FFI_EXPORT " +
    c_return +
    " " +
    bridge_name +
    "(" +
    c_params.join(", ") +
    ") {\n" +
    (if guards.length() == 0 {
      ""
    } else {
      "  if (" +
      guards.join(" || ") +
      ") { mbg_error[0] = 1; " +
      failure_return +
      " }\n"
    }) +
    "  mbg_error[0] = 0;\n  " +
    call_line +
    "\n}\n"
  (Some(moon), Some(c), "")
}
