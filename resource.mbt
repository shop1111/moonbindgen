///|
fn validate_v2_resources(
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
  for policy in config.resources {
    let create = match main.get(policy.create) {
      Some(value) if config.allows(policy.create) => value
      _ =>
        fail("unknown or filtered resource create function: " + policy.create)
    }
    if config.buffer_for(policy.create) is Some(_) ||
      config.return_buffer_for(policy.create) is Some(_) ||
      config.multi_output_for(policy.create) is Some(_) ||
      config.utf8_borrowed_returns.contains(policy.create) ||
      config.utf8_owned_returns.contains(policy.create) {
      fail("conflicting resource creation policy: " + policy.create)
    }
    let release = match all.get(policy.release) {
      Some(value) => value
      None => fail("unknown resource release function: " + policy.release)
    }
    let handle_type = normalized_type(create.canonical_return_type)
    if create.c_signature.contains("...") || !handle_type.has_suffix("*") {
      fail("resource create must return a pointer: " + policy.create)
    }
    if release.parameters.length() != 1 ||
      normalized_type(release.parameters[0].canonical_type) != handle_type ||
      release.c_signature.contains("...") {
      fail("resource release must accept the created handle: " + policy.release)
    }
    if policy.retain != "" {
      let retain = match all.get(policy.retain) {
        Some(value) => value
        None => fail("unknown resource retain function: " + policy.retain)
      }
      if normalized_type(retain.canonical_return_type) != "void" ||
        retain.parameters.length() != 1 ||
        normalized_type(retain.parameters[0].canonical_type) != handle_type ||
        retain.c_signature.contains("...") {
        fail(
          "resource retain must be void and accept the created handle: " +
          policy.retain,
        )
      }
    }
    for view_name in policy.views {
      if config.buffer_for(view_name) is Some(_) ||
        config.return_buffer_for(view_name) is Some(_) ||
        config.multi_output_for(view_name) is Some(_) {
        fail("conflicting resource view policy: " + view_name)
      }
      let view = match main.get(view_name) {
        Some(value) if config.allows(view_name) => value
        _ => fail("unknown or filtered resource view function: " + view_name)
      }
      if view.c_signature.contains("...") ||
        view.parameters.length() != 1 ||
        normalized_type(view.parameters[0].canonical_type) != handle_type ||
        normalized_type(view.canonical_return_type) != handle_type {
        fail("resource view must take and return the same handle: " + view_name)
      }
    }
  }
}

///|
fn v2_resource_needs_manual_release(
  nodes : Array[LocatedNode],
  config : GenerateConfig,
  name : String,
) -> Bool {
  guard config.resource_create_for(name) is Some(policy) else { return false }
  for entry in nodes {
    if text_field(entry.node, "kind") == Some("FunctionDecl") &&
      text_field(entry.node, "name") == Some(policy.release) {
      match c_function(entry.node, entry.source) {
        Some(function) =>
          return normalized_type(function.canonical_return_type) != "void"
        None => return true
      }
    }
  }
  true
}

///|
fn render_v2_resource_create(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  config : GenerateConfig,
) -> (String?, String?, String) {
  guard config.resource_create_for(function.name) is Some(policy) else {
    return (None, None, "missing resource policy")
  }
  let handle_type = match
    resolve_type(
      function.canonical_return_type,
      aliases,
      opaque_types,
      enums,
      result=true,
    ) {
    Some(value) if value.has_prefix("C_") => value
    _ => return (None, None, "resource create must return an opaque handle")
  }
  if handle_type != "C_" + policy.name {
    return (None, None, "resource name must match the opaque C type")
  }
  let resource_type = "MbgResource_" + policy.name
  let state_type = "mbg_state_" + policy.name
  let bridge_name = "mbg_resource_" + function.moon_name
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
  let raw_name = function.moon_name + "_raw"
  let raw_line = v2_extern(raw_name, moon_params, handle_type)
    .replace_all(old="extern \"C\"", new="pub extern \"C\"")
    .replace_all(old="\"" + raw_name + "\"", new="\"" + function.symbol + "\"")
  let moon = "///|\n" +
    "pub type " +
    resource_type +
    "\n\n" +
    "///|\n" +
    (if borrowed.length() == 0 {
      ""
    } else {
      "#borrow(" + borrowed.join(", ") + ")\n"
    }) +
    raw_line +
    "\n" +
    "///|\n" +
    (if borrowed.length() == 0 {
      ""
    } else {
      "#borrow(" + borrowed.join(", ") + ")\n"
    }) +
    v2_extern(bridge_name, ffi_params, resource_type) +
    "\n" +
    "///|\n#borrow(state)\n" +
    v2_extern(bridge_name + "_error", ["state : " + resource_type], "Int") +
    "\n" +
    "///|\n#borrow(state)\n" +
    v2_extern(bridge_name + "_valid", ["state : " + resource_type], "Bool") +
    "\n" +
    "///|\n#borrow(state)\n" +
    v2_extern(bridge_name + "_close", ["state : " + resource_type], "Bool") +
    "\n" +
    "///|\n#borrow(state)\n" +
    v2_extern(bridge_name + "_raw", ["state : " + resource_type], handle_type) +
    "\n" +
    (if policy.retain == "" {
      ""
    } else {
      "///|\n#borrow(state)\n" +
      v2_extern(
        bridge_name + "_retain",
        ["state : " + resource_type],
        resource_type,
      ) +
      "\n"
    }) +
    "///|\n" +
    v2_public_head(function.moon_name, moon_params) +
    " -> " +
    resource_type +
    "? raise {\n  let state = " +
    bridge_name +
    "(" +
    ffi_args.join(", ") +
    ")\n  if " +
    bridge_name +
    "_error(state) != 0 {\n    fail(\"C scalar argument is out of range\")\n  }\n" +
    "  if " +
    bridge_name +
    "_valid(state) { Some(state) } else { None }\n}\n\n" +
    "///|\npub fn " +
    resource_type +
    "::close(self : " +
    resource_type +
    ") -> Bool {\n  " +
    bridge_name +
    "_close(self)\n}\n\n" +
    "///|\npub fn " +
    resource_type +
    "::is_closed(self : " +
    resource_type +
    ") -> Bool {\n  !" +
    bridge_name +
    "_valid(self)\n}\n\n" +
    "///|\npub fn " +
    resource_type +
    "::unsafe_raw(self : " +
    resource_type +
    ") -> " +
    handle_type +
    " raise {\n  if self.is_closed() {\n" +
    "    fail(\"resource is closed\")\n  }\n  " +
    bridge_name +
    "_raw(self)\n}\n\n" +
    "///|\npub fn[T] " +
    resource_type +
    "::with_raw(self : " +
    resource_type +
    ", action : (" +
    handle_type +
    ") -> T) -> T raise {\n" +
    "  if self.is_closed() {\n    fail(\"resource is closed\")\n  }\n" +
    "  let result = action(" +
    bridge_name +
    "_raw(self))\n  ignore(self.is_closed())\n  result\n}\n" +
    (if policy.retain == "" {
      ""
    } else {
      "\n///|\npub fn " +
      resource_type +
      "::retain(self : " +
      resource_type +
      ") -> " +
      resource_type +
      " raise {\n  if self.is_closed() {\n" +
      "    fail(\"resource is closed\")\n  }\n  " +
      bridge_name +
      "_retain(self)\n}\n"
    })
  let c = "typedef struct {\n  " +
    function.return_type +
    " handle;\n" +
    "  int32_t error;\n} " +
    state_type +
    ";\n" +
    "static void " +
    bridge_name +
    "_finalize(void *raw) {\n" +
    "  " +
    state_type +
    " *state = (" +
    state_type +
    " *)raw;\n" +
    "  if (state->handle != NULL) {\n    " +
    function.return_type +
    " handle = state->handle;\n    state->handle = NULL;\n    " +
    policy.release +
    "(handle);\n  }\n}\n" +
    "MOONBIT_FFI_EXPORT " +
    state_type +
    " *" +
    bridge_name +
    "(" +
    c_params.join(", ") +
    ") {\n  " +
    state_type +
    " *state = (" +
    state_type +
    " *)moonbit_make_external_object(" +
    bridge_name +
    "_finalize, sizeof(" +
    state_type +
    "));\n" +
    "  state->handle = NULL;\n  state->error = 0;\n" +
    (if guards.length() == 0 {
      ""
    } else {
      "  if (" + guards.join(" || ") + ") { state->error = 1; return state; }\n"
    }) +
    "  state->handle = " +
    function.name +
    "(" +
    c_args.join(", ") +
    ");\n  return state;\n}\n" +
    "MOONBIT_FFI_EXPORT int32_t " +
    bridge_name +
    "_error(" +
    state_type +
    " *state) { return state->error; }\n" +
    "MOONBIT_FFI_EXPORT int32_t " +
    bridge_name +
    "_valid(" +
    state_type +
    " *state) { return state->handle != NULL; }\n" +
    "MOONBIT_FFI_EXPORT int32_t " +
    bridge_name +
    "_close(" +
    state_type +
    " *state) {\n  if (state->handle == NULL) return 0;\n  " +
    function.return_type +
    " handle = state->handle;\n" +
    "  state->handle = NULL;\n  " +
    policy.release +
    "(handle);\n  return 1;\n}\n" +
    "MOONBIT_FFI_EXPORT " +
    function.return_type +
    " " +
    bridge_name +
    "_raw(void *state_raw) { " +
    state_type +
    " *state = (" +
    state_type +
    " *)state_raw; return state->handle; }\n" +
    (if policy.retain == "" {
      ""
    } else {
      "MOONBIT_FFI_EXPORT " +
      state_type +
      " *" +
      bridge_name +
      "_retain(" +
      state_type +
      " *state) {\n" +
      "  " +
      state_type +
      " *copy = (" +
      state_type +
      " *)moonbit_make_external_object(" +
      bridge_name +
      "_finalize, sizeof(" +
      state_type +
      "));\n" +
      "  copy->handle = NULL;\n  copy->error = 0;\n" +
      "  if (state->handle != NULL) {\n    " +
      policy.retain +
      "(state->handle);\n    copy->handle = state->handle;\n" +
      "  }\n  return copy;\n}\n"
    })
  (Some(moon), Some(c), "")
}

///|
fn render_v2_resource_view(
  function : CFunction,
  config : GenerateConfig,
) -> (String?, String?, String) {
  guard config.resource_view_for(function.name) is Some(policy) else {
    return (None, None, "missing resource view policy")
  }
  let create_name = moonbit_value_name(config.renamed(policy.create))
  let resource_type = "MbgResource_" + policy.name
  let view_type = "MbgView_" + function.moon_name
  let handle_type = "C_" + policy.name
  let bridge_name = "mbg_view_" + function.moon_name
  let resource_getter = "mbg_resource_" + create_name + "_raw"
  let raw_name = function.moon_name + "_raw"
  let raw_line = v2_extern(raw_name, ["raw : " + handle_type], handle_type)
    .replace_all(old="extern \"C\"", new="pub extern \"C\"")
    .replace_all(old="\"" + raw_name + "\"", new="\"" + function.symbol + "\"")
  let moon = "///|\npub struct " +
    view_type +
    " {\n" +
    "  owner : " +
    resource_type +
    "\n  raw : " +
    handle_type +
    "\n}\n\n" +
    "///|\n" +
    raw_line +
    "\n" +
    "///|\n#borrow(owner, absent)\n" +
    v2_extern(
      bridge_name,
      ["owner : " + resource_type, "absent : FixedArray[Int]"],
      handle_type,
    ) +
    "\n" +
    "///|\npub fn " +
    function.moon_name +
    "(owner : " +
    resource_type +
    ") -> " +
    view_type +
    "? raise {\n" +
    "  let absent = FixedArray::make(1, 0)\n" +
    "  let raw = " +
    bridge_name +
    "(owner, absent)\n" +
    "  if absent[0] == 2 {\n    fail(\"resource is closed\")\n" +
    "  } else if absent[0] == 1 {\n    None\n" +
    "  } else {\n    Some({ owner, raw, })\n  }\n}\n\n" +
    "///|\npub fn " +
    view_type +
    "::unsafe_raw(self : " +
    view_type +
    ") -> " +
    handle_type +
    " raise {\n" +
    "  if self.owner.is_closed() {\n    fail(\"resource is closed\")\n" +
    "  }\n  self.raw\n}\n\n" +
    "///|\npub fn[T] " +
    view_type +
    "::with_raw(self : " +
    view_type +
    ", action : (" +
    handle_type +
    ") -> T) -> T raise {\n" +
    "  if self.owner.is_closed() {\n    fail(\"resource is closed\")\n  }\n" +
    "  let result = action(self.raw)\n" +
    "  ignore(self.owner.is_closed())\n  result\n}\n"
  let c = "extern " +
    function.return_type +
    " " +
    resource_getter +
    "(void *state_raw);\n" +
    "MOONBIT_FFI_EXPORT " +
    function.return_type +
    " " +
    bridge_name +
    "(void *owner, int32_t *absent) {\n" +
    "  " +
    function.return_type +
    " handle = " +
    resource_getter +
    "(owner);\n" +
    "  if (handle == NULL) { absent[0] = 2; return NULL; }\n" +
    "  " +
    function.return_type +
    " view = " +
    function.name +
    "(handle);\n" +
    "  absent[0] = view == NULL ? 1 : 0;\n  return view;\n}\n"
  (Some(moon), Some(c), "")
}
