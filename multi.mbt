///|
priv struct MultiField {
  index : Int
  name : String
  c_type : String
  moon_type : String
  ffi_c_type : String
}

///|
fn v2_multi_field(
  output : NamedOutput,
  parameter : CParameter,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
) -> MultiField? {
  let shape = c_type_model(parameter.canonical_type)
  if shape.pointer_depth == 0 ||
    shape.pointee_const ||
    shape.array ||
    shape.function_pointer ||
    parameter.canonical_type.contains(" const ") {
    return None
  }
  let raw = parameter.c_type.trim().to_owned()
  let canonical = parameter.canonical_type.trim().to_owned()
  if !raw.has_suffix("*") || !canonical.has_suffix("*") {
    return None
  }
  let c_type = raw[:raw.length() - 1].trim().to_owned()
  let canonical_value = canonical[:canonical.length() - 1].trim().to_owned()
  let kind = v2_abi_kind(c_type, canonical_value)
  let moon_type = if kind != "" {
    v2_abi_moon_type(kind)
  } else {
    match
      resolve_type(canonical_value, aliases, opaque_types, enums, result=false) {
      Some(value) => value
      None => return None
    }
  }
  let ffi_c_type = if kind != "" { v2_abi_c_type(kind) } else { c_type }
  Some({
    index: output.index,
    name: output.name,
    c_type,
    moon_type,
    ffi_c_type,
  })
}

///|
fn validate_v2_multi_outputs(
  nodes : Array[LocatedNode],
  header : String,
  config : GenerateConfig,
) -> Unit raise {
  if config.schema_version != 2 {
    return
  }
  let main : Map[String, CFunction] = Map([])
  for entry in nodes {
    if text_field(entry.node, "kind") == Some("FunctionDecl") &&
      same_header(entry.source.file, header) {
      match c_function(entry.node, entry.source) {
        Some(function) => main[function.name] = function
        None => ()
      }
    }
  }
  for policy in config.multi_outputs {
    let function = match main.get(policy.function_name) {
      Some(value) if config.allows(policy.function_name) => value
      _ =>
        fail(
          "unknown or filtered multi-output function: " + policy.function_name,
        )
    }
    if config.buffer_for(function.name) is Some(_) ||
      config.return_buffer_for(function.name) is Some(_) ||
      config.utf8_borrowed_returns.contains(function.name) ||
      config.utf8_owned_returns.contains(function.name) {
      fail("conflicting multi-output policy: " + function.name)
    }
    for key, _ in config.output_params {
      if key.has_prefix(function.name + ".") {
        fail(
          "legacy output policy conflicts with multi-output: " + function.name,
        )
      }
    }
    if function.c_signature.contains("...") ||
      (
        normalized_type(function.canonical_return_type) != "int" &&
        normalized_type(function.canonical_return_type) != "void"
      ) {
      fail("multi-output function must return int or void: " + function.name)
    }
    for output in policy.outputs {
      if output.index >= function.parameters.length() {
        fail("multi-output index is out of range: " + function.name)
      }
    }
  }
}

///|
fn render_v2_multi_output(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  config : GenerateConfig,
) -> (String?, String?, String) {
  guard config.multi_output_for(function.name) is Some(policy) else {
    return (None, None, "missing multi-output policy")
  }
  let fields : Array[MultiField] = []
  let output_by_index : Map[Int, MultiField] = Map([])
  for output in policy.outputs {
    if output.index >= function.parameters.length() {
      return (None, None, "multi-output index is out of range")
    }
    let field = match
      v2_multi_field(
        output,
        function.parameters[output.index],
        aliases,
        opaque_types,
        enums,
      ) {
      Some(value) => value
      None =>
        return (
          None,
          None,
          "unsupported output type at position " + output.index.to_string(),
        )
    }
    fields.push(field)
    output_by_index[output.index] = field
  }
  let moon_params : Array[String] = []
  let ffi_params : Array[String] = []
  let ffi_args : Array[String] = []
  let c_params : Array[String] = []
  let c_args : Array[String] = []
  let borrowed : Array[String] = []
  let guards : Array[String] = []
  for index, parameter in function.parameters {
    match output_by_index.get(index) {
      Some(_) => c_args.push("&mbg_result->out" + index.to_string())
      None => {
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
              return (
                None,
                None,
                "unsupported parameter type: " + parameter.c_type,
              )
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
    }
  }
  let result_name = "MbgResult_" + function.moon_name
  let raw_name = "MbgRaw_" + function.moon_name
  let bridge_name = "mbg_bridge_" + function.moon_name
  let returns_status = normalized_type(function.canonical_return_type) == "int"
  let moon_fields : Array[String] = []
  let constructor_fields : Array[String] = []
  let getters : Array[String] = []
  let c_fields : Array[String] = ["  int32_t error;"]
  let c_getters : Array[String] = []
  if returns_status {
    moon_fields.push("  status : Int")
    constructor_fields.push("    status: " + bridge_name + "_status(raw),")
    c_fields.push("  int32_t status;")
    getters.push(
      "///|\n#borrow(raw)\n" +
      v2_extern(bridge_name + "_status", ["raw : " + raw_name], "Int"),
    )
    c_getters.push(
      "MOONBIT_FFI_EXPORT int32_t " +
      bridge_name +
      "_status(" +
      bridge_name +
      "_result *raw) { return raw->status; }\n",
    )
  }
  for field in fields {
    let suffix = field.index.to_string()
    moon_fields.push("  " + field.name + " : " + field.moon_type)
    constructor_fields.push(
      "    " + field.name + ": " + bridge_name + "_out" + suffix + "(raw),",
    )
    c_fields.push("  " + field.c_type + " out" + suffix + ";")
    getters.push(
      "///|\n#borrow(raw)\n" +
      v2_extern(
        bridge_name + "_out" + suffix,
        ["raw : " + raw_name],
        field.moon_type,
      ),
    )
    c_getters.push(
      "MOONBIT_FFI_EXPORT " +
      field.ffi_c_type +
      " " +
      bridge_name +
      "_out" +
      suffix +
      "(" +
      bridge_name +
      "_result *raw) { return (" +
      field.ffi_c_type +
      ")raw->out" +
      suffix +
      "; }\n",
    )
  }
  let call = function.name + "(" + c_args.join(", ") + ")"
  let moon = "///|\n" +
    "type " +
    raw_name +
    "\n\n" +
    "///|\npub(all) struct " +
    result_name +
    " {\n" +
    moon_fields.join("\n") +
    "\n}\n\n" +
    "///|\n" +
    (if borrowed.length() == 0 {
      ""
    } else {
      "#borrow(" + borrowed.join(", ") + ")\n"
    }) +
    v2_extern(bridge_name, ffi_params, raw_name) +
    "\n" +
    "///|\n#borrow(raw)\n" +
    v2_extern(bridge_name + "_error", ["raw : " + raw_name], "Int") +
    "\n" +
    getters.join("\n") +
    "\n///|\n" +
    v2_public_head(function.moon_name, moon_params) +
    " -> " +
    result_name +
    " raise {\n  let raw = " +
    bridge_name +
    "(" +
    ffi_args.join(", ") +
    ")\n  if " +
    bridge_name +
    "_error(raw) != 0 {\n    fail(\"C scalar argument is out of range\")\n  }\n" +
    "  {\n" +
    constructor_fields.join("\n") +
    "\n  }\n}\n"
  let c = "typedef struct {\n" +
    c_fields.join("\n") +
    "\n} " +
    bridge_name +
    "_result;\n" +
    "static void " +
    bridge_name +
    "_finalize(void *raw) { (void)raw; }\n" +
    "MOONBIT_FFI_EXPORT " +
    bridge_name +
    "_result *" +
    bridge_name +
    "(" +
    c_params.join(", ") +
    ") {\n" +
    "  " +
    bridge_name +
    "_result *mbg_result = (" +
    bridge_name +
    "_result *)moonbit_make_external_object(" +
    bridge_name +
    "_finalize, sizeof(" +
    bridge_name +
    "_result));\n" +
    "  memset(mbg_result, 0, sizeof(*mbg_result));\n" +
    (if guards.length() == 0 {
      ""
    } else {
      "  if (" +
      guards.join(" || ") +
      ") { mbg_result->error = 1; return mbg_result; }\n"
    }) +
    "  " +
    (if returns_status { "mbg_result->status = " } else { "" }) +
    call +
    ";\n  return mbg_result;\n}\n" +
    "MOONBIT_FFI_EXPORT int32_t " +
    bridge_name +
    "_error(" +
    bridge_name +
    "_result *raw) { return raw->error; }\n" +
    c_getters.join("")
  (Some(moon), Some(c), "")
}
