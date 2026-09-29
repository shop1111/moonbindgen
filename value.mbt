///|
priv struct ValueField {
  name : String
  c_type : String
  moon_type : String
  ffi_c_type : String
  abi_kind : String
}

///|
priv struct ValueRecord {
  name : String
  fields : Array[ValueField]
  reason : String
}

///|
fn value_field(
  node : Json,
  aliases : Map[String, String],
  enums : Map[String, Bool],
) -> ValueField? {
  guard text_field(node, "name") is Some(name) &&
    type_spelling(node) is Some(c_type) else {
    return None
  }
  if field(node, "isBitfield") == Some(Json::boolean(true)) ||
    !valid_c_identifier(name) ||
    moonbit_value_name(name) != name {
    return None
  }
  let canonical = canonical_type_spelling(node).unwrap_or(c_type)
  let shape = c_type_model(canonical)
  if shape.pointer_depth != 0 ||
    shape.array ||
    shape.function_pointer ||
    shape.record ||
    c_type.contains("[") ||
    canonical.contains("[") {
    return None
  }
  let kind = v2_abi_kind(c_type, canonical)
  let moon_type = if kind != "" {
    v2_abi_moon_type(kind)
  } else {
    match resolve_type(canonical, aliases, Map([]), enums, result=false) {
      Some(value) if value != "Unit" && !value.has_prefix("C_") => value
      _ => return None
    }
  }
  let ffi_c_type = if kind != "" {
    v2_abi_c_type(kind)
  } else {
    match moon_type {
      "Byte" => "uint8_t"
      "Int" => "int32_t"
      "UInt" => "uint32_t"
      "Int64" => "int64_t"
      "UInt64" => "uint64_t"
      "Float" => "float"
      "Double" => "double"
      _ => return None
    }
  }
  Some({ name, c_type, moon_type, ffi_c_type, abi_kind: kind, })
}

///|
fn value_records(
  nodes : Array[LocatedNode],
  aliases : Map[String, String],
  enums : Map[String, Bool],
) -> Map[String, ValueRecord] {
  let records : Map[String, ValueRecord] = Map([])
  for entry in nodes {
    let node = entry.node
    if text_field(node, "kind") != Some("RecordDecl") ||
      text_field(node, "tagUsed") != Some("struct") ||
      field(node, "completeDefinition") != Some(Json::boolean(true)) {
      continue
    }
    guard text_field(node, "name") is Some(name) && valid_c_identifier(name) else {
      continue
    }
    let fields : Array[ValueField] = []
    let mut reason = ""
    for child in array_field(node, "inner") {
      if text_field(child, "kind") == Some("FieldDecl") {
        match value_field(child, aliases, enums) {
          Some(value) => fields.push(value)
          None => reason = "non-scalar, bit-field, array, or anonymous field"
        }
      }
    }
    if fields.length() == 0 {
      reason = "record has no scalar fields"
    }
    records[name] = { name, fields, reason, }
  }
  records
}

///|
fn value_record_for(
  raw : String,
  aliases : Map[String, String],
  records : Map[String, ValueRecord],
) -> ValueRecord? {
  let mut source = normalized_type(raw)
  for _ in 0..<16 {
    if source.has_prefix("struct ") {
      return records.get(source[7:].to_owned())
    }
    match records.get(source) {
      Some(record) => return Some(record)
      None => ()
    }
    match aliases.get(source) {
      Some(next) => source = normalized_type(next)
      None => return None
    }
  }
  None
}

///|
fn uses_v2_value_record(
  function : CFunction,
  config : GenerateConfig,
  aliases : Map[String, String],
  records : Map[String, ValueRecord],
) -> Bool {
  if config.schema_version != 2 {
    return false
  }
  if value_record_for(function.return_type, aliases, records) is Some(_) {
    return true
  }
  for parameter in function.parameters {
    if value_record_for(parameter.c_type, aliases, records) is Some(_) {
      return true
    }
  }
  false
}

///|
fn value_record_decl(record : ValueRecord) -> String {
  let fields : Array[String] = []
  for field in record.fields {
    fields.push("  " + field.name + " : " + field.moon_type)
  }
  "///|\npub(all) struct MbgValue_" +
  record.name +
  " {\n" +
  fields.join("\n") +
  "\n}\n"
}

///|
fn value_field_size_check(
  c_record : String,
  field : ValueField,
  suffix : String,
) -> String {
  if field.abi_kind != "" {
    return ""
  }
  "  typedef char mbg_check_" +
  suffix +
  "_" +
  field.name +
  "[(sizeof(( (" +
  c_record +
  " *)0)->" +
  field.name +
  ") == sizeof(" +
  field.ffi_c_type +
  ")) ? 1 : -1];"
}

///|
fn render_v2_value_function(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  records : Map[String, ValueRecord],
  config : GenerateConfig,
  used : Map[String, Bool],
) -> (String?, String?, String) {
  if function.c_signature.contains("...") {
    return (None, None, "variadic function")
  }
  if config.buffer_for(function.name) is Some(_) ||
    config.return_buffer_for(function.name) is Some(_) ||
    config.multi_output_for(function.name) is Some(_) ||
    config.resource_create_for(function.name) is Some(_) ||
    config.resource_view_for(function.name) is Some(_) {
    return (None, None, "value record conflicts with another bridge policy")
  }
  let return_record = value_record_for(function.return_type, aliases, records)
  let return_kind = v2_abi_kind(
    function.return_type,
    function.canonical_return_type,
  )
  let moon_return = match return_record {
    Some(record) => {
      if record.reason != "" {
        return (
          None,
          None,
          "unsupported value record " + record.name + ": " + record.reason,
        )
      }
      "MbgValue_" + record.name
    }
    None =>
      if return_kind != "" {
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
            return (
              None,
              None,
              "unsupported return type: " + function.return_type,
            )
        }
      }
  }
  let bridge = "mbg_value_" + function.moon_name
  let raw_type = "MbgRawValue_" + function.moon_name
  let moon_params : Array[String] = []
  let ffi_params : Array[String] = []
  let ffi_args : Array[String] = []
  let c_params : Array[String] = []
  let c_args : Array[String] = []
  let local_lines : Array[String] = []
  let abi_checks : Array[String] = []
  let guards : Array[String] = []
  let borrowed : Array[String] = []
  let pending_used : Array[String] = []
  for index, parameter in function.parameters {
    let arg = "arg" + index.to_string()
    let c_arg = "p" + index.to_string()
    match value_record_for(parameter.c_type, aliases, records) {
      Some(record) => {
        if record.reason != "" {
          return (
            None,
            None,
            "unsupported value record " + record.name + ": " + record.reason,
          )
        }
        pending_used.push(record.name)
        moon_params.push(arg + " : MbgValue_" + record.name)
        local_lines.push(
          "  " + parameter.c_type + " value" + index.to_string() + ";",
        )
        local_lines.push(
          "  memset(&value" +
          index.to_string() +
          ", 0, sizeof(value" +
          index.to_string() +
          "));",
        )
        c_args.push("value" + index.to_string())
        for field in record.fields {
          let size_check = value_field_size_check(
            parameter.c_type,
            field,
            index.to_string(),
          )
          if size_check != "" {
            abi_checks.push(size_check)
          }
          let flat = c_arg + "_" + field.name
          ffi_params.push(flat + " : " + field.moon_type)
          ffi_args.push(arg + "." + field.name)
          c_params.push(field.ffi_c_type + " " + flat)
          let check = v2_abi_range_check(field.abi_kind, flat)
          if check != "" {
            guards.push(check)
          }
          local_lines.push(
            "  value" +
            index.to_string() +
            "." +
            field.name +
            " = (" +
            field.c_type +
            ")" +
            flat +
            ";",
          )
        }
      }
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
        moon_params.push(arg + " : " + moon_type)
        ffi_params.push(arg + " : " + moon_type)
        ffi_args.push(arg)
        if kind != "" {
          c_params.push(v2_abi_c_type(kind) + " " + c_arg)
          c_args.push("(" + parameter.c_type + ")" + c_arg)
          let check = v2_abi_range_check(kind, c_arg)
          if check != "" {
            guards.push(check)
          }
        } else if moon_type == "Bytes" {
          borrowed.push(arg)
          c_params.push("moonbit_bytes_t " + c_arg)
          c_args.push("(" + parameter.c_type + ")" + c_arg)
        } else {
          c_params.push(parameter.c_type + " " + c_arg)
          c_args.push(c_arg)
        }
      }
    }
  }
  let mut c_value_type = function.return_type
  if return_kind != "" {
    c_value_type = function.return_type
  }
  let moon_getters : Array[String] = []
  let c_getters : Array[String] = []
  let mut moon_value = "()"
  match return_record {
    Some(record) => {
      pending_used.push(record.name)
      let values : Array[String] = []
      for field in record.fields {
        let size_check = value_field_size_check(
          function.return_type,
          field,
          "return",
        )
        if size_check != "" {
          abi_checks.push(size_check)
        }
        let getter = bridge + "_" + field.name
        moon_getters.push(
          "///|\n#borrow(raw)\n" +
          v2_extern(getter, ["raw : " + raw_type], field.moon_type),
        )
        c_getters.push(
          "MOONBIT_FFI_EXPORT " +
          field.ffi_c_type +
          " " +
          getter +
          "(" +
          bridge +
          "_result *raw) { return (" +
          field.ffi_c_type +
          ")raw->value." +
          field.name +
          "; }\n",
        )
        values.push("    " + field.name + ": " + getter + "(raw),")
      }
      moon_value = "{\n" + values.join("\n") + "\n  }"
    }
    None =>
      if moon_return != "Unit" {
        let getter = bridge + "_value"
        let c_getter_type = if return_kind != "" {
          v2_abi_c_type(return_kind)
        } else {
          c_value_type
        }
        moon_getters.push(
          "///|\n#borrow(raw)\n" +
          v2_extern(getter, ["raw : " + raw_type], moon_return),
        )
        c_getters.push(
          "MOONBIT_FFI_EXPORT " +
          c_getter_type +
          " " +
          getter +
          "(" +
          bridge +
          "_result *raw) { return (" +
          c_getter_type +
          ")raw->value; }\n",
        )
        moon_value = getter + "(raw)"
      }
  }
  let call = function.name + "(" + c_args.join(", ") + ")"
  let c_call = if moon_return == "Unit" {
    call + ";"
  } else {
    "raw->value = " + call + ";"
  }
  let moon = "///|\ntype " +
    raw_type +
    "\n\n" +
    "///|\n" +
    (if borrowed.length() == 0 {
      ""
    } else {
      "#borrow(" + borrowed.join(", ") + ")\n"
    }) +
    v2_extern(bridge, ffi_params, raw_type) +
    "\n" +
    "///|\n#borrow(raw)\n" +
    v2_extern(bridge + "_error", ["raw : " + raw_type], "Int") +
    "\n" +
    moon_getters.join("\n") +
    "\n///|\n" +
    v2_public_head(function.moon_name, moon_params) +
    " -> " +
    moon_return +
    " raise {\n" +
    "  let raw = " +
    bridge +
    "(" +
    ffi_args.join(", ") +
    ")\n" +
    "  if " +
    bridge +
    "_error(raw) != 0 {\n    fail(\"C scalar argument is out of range\")\n  }\n" +
    "  " +
    moon_value +
    "\n}\n"
  let c = "typedef struct {\n  int32_t error;\n" +
    (if moon_return == "Unit" { "" } else { "  " + c_value_type + " value;\n" }) +
    "} " +
    bridge +
    "_result;\n" +
    "static void " +
    bridge +
    "_finalize(void *raw) { (void)raw; }\n" +
    "MOONBIT_FFI_EXPORT " +
    bridge +
    "_result *" +
    bridge +
    "(" +
    c_params.join(", ") +
    ") {\n" +
    abi_checks.join("\n") +
    "\n" +
    "  " +
    bridge +
    "_result *raw = (" +
    bridge +
    "_result *)moonbit_make_external_object(" +
    bridge +
    "_finalize, sizeof(" +
    bridge +
    "_result));\n" +
    "  memset(raw, 0, sizeof(*raw));\n" +
    (if guards.length() == 0 {
      ""
    } else {
      "  if (" + guards.join(" || ") + ") { raw->error = 1; return raw; }\n"
    }) +
    local_lines.join("\n") +
    "\n  " +
    c_call +
    "\n  return raw;\n}\n" +
    "MOONBIT_FFI_EXPORT int32_t " +
    bridge +
    "_error(" +
    bridge +
    "_result *raw) { return raw->error; }\n" +
    c_getters.join("")
  for name in pending_used {
    used[name] = true
  }
  (Some(moon), Some(c), "")
}
