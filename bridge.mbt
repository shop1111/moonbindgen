///|
fn validate_bridge_config(
  nodes : Array[LocatedNode],
  header : String,
  config : GenerateConfig,
) -> Unit raise {
  let main_functions : Map[String, CFunction] = Map([])
  let all_functions : Map[String, CFunction] = Map([])
  for entry in nodes {
    if text_field(entry.node, "kind") == Some("FunctionDecl") {
      match c_function(entry.node, entry.source) {
        Some(function) => {
          all_functions[function.name] = function
          if same_header(entry.source.file, header) {
            main_functions[function.name] = function
          }
        }
        None => ()
      }
    }
  }
  for key, _ in config.output_params {
    validate_parameter_key(key, main_functions)
    let parts = key.split(".").to_array()
    if !config.allows(parts[0].to_owned()) {
      fail("configured bridge function is filtered: " + key)
    }
  }
  for key, _ in config.null_inputs {
    validate_parameter_key(key, main_functions)
    let parts = key.split(".").to_array()
    if !config.has_bridge(parts[0].to_owned()) ||
      !config.allows(parts[0].to_owned()) {
      fail("null_inputs requires a bridged function: " + key)
    }
  }
  for name, _ in config.utf8_borrowed_returns {
    if !main_functions.contains(name) || !config.allows(name) {
      fail("unknown UTF-8 return function: " + name)
    }
  }
  for name, free_name in config.utf8_owned_returns {
    if !main_functions.contains(name) || !config.allows(name) {
      fail("unknown UTF-8 return function: " + name)
    }
    match all_functions.get(free_name) {
      Some(free_function) => {
        if normalized_type(free_function.canonical_return_type) != "void" ||
          free_function.parameters.length() != 1 ||
          free_function.c_signature.contains("...") {
          fail("invalid string release function: " + free_name)
        }
        let argument = normalized_type(
          free_function.parameters[0].canonical_type,
        )
        if argument != "void*" && argument != "char*" {
          fail("invalid string release function: " + free_name)
        }
      }
      None => fail("unknown string release function: " + free_name)
    }
  }
}

///|
fn validate_parameter_key(
  key : String,
  functions : Map[String, CFunction],
) -> Unit raise {
  let parts = key.split(".").to_array()
  if parts.length() != 2 {
    fail("expected function.parameter: " + key)
  }
  match functions.get(parts[0].to_owned()) {
    Some(function) => {
      for parameter in function.parameters {
        if parameter.name == parts[1].to_owned() {
          return
        }
      }
      fail("unknown parameter: " + key)
    }
    None => fail("unknown function: " + key)
  }
}

///|
fn render_bridge(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  config : GenerateConfig,
) -> (String?, String?, String) {
  if function.c_signature.contains("...") {
    return (None, None, "variadic function")
  }
  let string_return = config.utf8_borrowed_returns.contains(function.name) ||
    config.utf8_owned_returns.contains(function.name)
  let mut output_count = 0
  let mut output_moon_type = ""
  let mut output_c_type = ""
  let moon_params : Array[String] = []
  let moon_args : Array[String] = []
  let c_params : Array[String] = []
  let c_args : Array[String] = []
  let borrowed : Array[String] = []
  let used_names : Map[String, Int] = Map([])
  for index, parameter in function.parameters {
    let ctype = normalized_type(parameter.canonical_type)
    if config.is_output(function.name, parameter.name) {
      output_count += 1
      if !ctype.has_suffix("*") ||
        parameter.canonical_type.trim().has_prefix("const ") {
        return (
          None,
          None,
          "unsupported output parameter type: " + parameter.c_type,
        )
      }
      let pointee = ctype[:ctype.length() - 1].trim().to_owned()
      let resolved = resolve_type(
        pointee,
        aliases,
        opaque_types,
        enums,
        result=false,
      )
      match resolved {
        Some(value) => {
          output_moon_type = value
          output_c_type = pointee
          c_args.push("&mbg_value")
        }
        None =>
          return (
            None,
            None,
            "unsupported output parameter type: " + parameter.c_type,
          )
      }
    } else if config.is_null_input(function.name, parameter.name) {
      if !ctype.has_suffix("*") || ctype.contains("(") {
        return (None, None, "null input is not a pointer: " + parameter.name)
      }
      c_args.push("NULL")
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
      let base_name = moonbit_value_name(parameter.name)
      let count = used_names.get(base_name).unwrap_or(0) + 1
      used_names[base_name] = count
      let name = if count == 1 {
        base_name
      } else {
        base_name + "_" + count.to_string()
      }
      moon_params.push(name + " : " + resolved.moon_type)
      moon_args.push(name)
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
  if (string_return && output_count != 0) ||
    (!string_return && output_count != 1) {
    return (None, None, "bridge needs exactly one output or string return")
  }
  let bridge_name = "mbg_bridge_" + function.moon_name
  let ffi_params = moon_params.copy()
  let ffi_args = moon_args.copy()
  let c_signature = c_params.copy()
  let extra_name = if string_return { "mbg_absent" } else { "mbg_status" }
  ffi_params.push(extra_name + " : FixedArray[Int]")
  ffi_args.push(extra_name)
  c_signature.push("int32_t *" + extra_name)
  borrowed.push(extra_name)
  let ffi_borrow = "#borrow(" + borrowed.join(", ") + ")\n"
  let public_parameters = moon_params.join(", ")
  let call = function.name + "(" + c_args.join(", ") + ")"
  let ffi_return = if string_return { "Bytes" } else { output_moon_type }
  let ffi_line = "extern \"C\" fn " +
    bridge_name +
    "(" +
    ffi_params.join(", ") +
    ") -> " +
    ffi_return +
    " = \"" +
    bridge_name +
    "\"\n"
  let ffi_declaration = if ffi_params.length() > 2 || ffi_line.length() > 110 {
    "extern \"C\" fn " +
    bridge_name +
    "(\n" +
    ffi_params.map(param => "  " + param + ",").join("\n") +
    "\n) -> " +
    ffi_return +
    " = \"" +
    bridge_name +
    "\"\n"
  } else {
    ffi_line
  }
  let public_head = if moon_params.length() > 2 {
    "pub fn " +
    function.moon_name +
    "(\n" +
    moon_params.map(param => "  " + param + ",").join("\n") +
    "\n)"
  } else {
    "pub fn " + function.moon_name + "(" + public_parameters + ")"
  }
  if string_return {
    if normalized_type(function.canonical_return_type) != "char*" {
      return (None, None, "unsupported return type: " + function.return_type)
    }
    let owned_free = config.utf8_owned_returns.get(function.name)
    if owned_free is Some(_) &&
      !function.canonical_return_type.trim().has_prefix("char *") &&
      !function.canonical_return_type.trim().has_prefix("char*") {
      return (None, None, "owned string return must be char *")
    }
    let moon = "///|\n" +
      ffi_borrow +
      ffi_declaration +
      "\n///|\n" +
      public_head +
      " -> String? raise {\n" +
      "  let " +
      extra_name +
      " = FixedArray::make(1, 0)\n" +
      "  let bytes = " +
      bridge_name +
      "(" +
      ffi_args.join(", ") +
      ")\n" +
      "  if " +
      extra_name +
      "[0] == 1 {\n    None\n" +
      "  } else if " +
      extra_name +
      "[0] == 2 {\n" +
      "    fail(\"returned C string is too large\")\n" +
      "  } else {\n    Some(@utf8.decode(bytes))\n  }\n}\n"
    let c_type = if owned_free is Some(_) { "char *" } else { "const char *" }
    let free_line = match owned_free {
      Some(name) => "    " + name + "(mbg_text);\n"
      None => ""
    }
    let free_after_copy = match owned_free {
      Some(name) => "  " + name + "(mbg_text);\n"
      None => ""
    }
    let c = "MOONBIT_FFI_EXPORT moonbit_bytes_t " +
      bridge_name +
      "(" +
      c_signature.join(", ") +
      ") {\n  " +
      c_type +
      "mbg_text = " +
      call +
      ";\n  if (mbg_text == NULL) {\n    mbg_absent[0] = 1;\n" +
      "    return moonbit_make_bytes(0, 0);\n  }\n" +
      "  size_t mbg_size = strlen(mbg_text);\n" +
      "  if (mbg_size > INT32_MAX) {\n" +
      free_line +
      "    mbg_absent[0] = 2;\n    return moonbit_make_bytes(0, 0);\n  }\n" +
      "  mbg_absent[0] = 0;\n" +
      "  moonbit_bytes_t mbg_bytes = moonbit_make_bytes((int32_t)mbg_size, 0);\n" +
      "  memcpy(mbg_bytes, mbg_text, mbg_size);\n" +
      free_after_copy +
      "  return mbg_bytes;\n}\n"
    (Some(moon), Some(c), "")
  } else {
    if normalized_type(function.canonical_return_type) != "int" &&
      normalized_type(function.canonical_return_type) != "signed int" {
      return (None, None, "output function must return int status")
    }
    let moon = "///|\n" +
      ffi_borrow +
      ffi_declaration +
      "\n///|\n" +
      public_head +
      " -> (Int, " +
      output_moon_type +
      ") {\n" +
      "  let " +
      extra_name +
      " = FixedArray::make(1, 0)\n" +
      "  let value = " +
      bridge_name +
      "(" +
      ffi_args.join(", ") +
      ")\n" +
      "  (" +
      extra_name +
      "[0], value)\n}\n"
    let c = "MOONBIT_FFI_EXPORT " +
      output_c_type +
      " " +
      bridge_name +
      "(" +
      c_signature.join(", ") +
      ") {\n  " +
      output_c_type +
      " mbg_value = 0;\n  mbg_status[0] = " +
      call +
      ";\n  return mbg_value;\n}\n"
    (Some(moon), Some(c), "")
  }
}
