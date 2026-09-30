///|
priv struct CallbackShape {
  return_type : String
  parameters : Array[String]
}

///|
fn callback_shape(raw : String) -> CallbackShape? {
  let parts = raw.split("(*").to_array()
  if parts.length() != 2 {
    return None
  }
  let return_type = parts[0].trim().to_owned()
  let suffix = parts[1].trim().to_owned()
  if !suffix.has_prefix(")(") || !suffix.has_suffix(")") {
    return None
  }
  let args = suffix[2:suffix.length() - 1].trim().to_owned()
  let parameters : Array[String] = []
  if args != "" && args != "void" {
    for part in args.split(",") {
      parameters.push(part.trim().to_owned())
    }
  }
  Some({ return_type, parameters, })
}

///|
fn callback_direct_type(raw : String, result~ : Bool) -> String? {
  match normalized_type(raw) {
    "void" => if result { Some("Unit") } else { None }
    "int" | "signed int" => Some("Int")
    "unsigned int" => Some("UInt")
    "float" => Some("Float")
    "double" => Some("Double")
    _ => None
  }
}

///|
fn call_callback_type(shape : CallbackShape) -> String? {
  let return_type = match callback_direct_type(shape.return_type, result=true) {
    Some(value) => value
    None => return None
  }
  let parameters : Array[String] = []
  for parameter in shape.parameters {
    match callback_direct_type(parameter, result=false) {
      Some(value) => parameters.push(value)
      None => return None
    }
  }
  Some("FuncRef[(" + parameters.join(", ") + ") -> " + return_type + "]")
}

///|
fn validate_v2_callbacks(
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
  for policy in config.callbacks {
    let function = match main.get(policy.function_name) {
      Some(value) if config.allows(policy.function_name) => value
      _ =>
        fail("unknown or filtered callback function: " + policy.function_name)
    }
    if policy.callback >= function.parameters.length() ||
      function.c_signature.contains("...") {
      fail(
        "callback position or variadic signature is unsupported: " +
        function.name,
      )
    }
    if config.buffer_for(function.name) is Some(_) ||
      config.return_buffer_for(function.name) is Some(_) ||
      config.multi_output_for(function.name) is Some(_) ||
      config.resource_create_for(function.name) is Some(_) ||
      config.resource_view_for(function.name) is Some(_) {
      fail("callback conflicts with another bridge policy: " + function.name)
    }
    let shape = match
      callback_shape(function.parameters[policy.callback].canonical_type) {
      Some(value) => value
      None =>
        fail("callback parameter is not a function pointer: " + function.name)
    }
    if policy.lifetime == "call" {
      if call_callback_type(shape) is None {
        fail(
          "call-scoped callback has unsupported scalar ABI: " + function.name,
        )
      }
    } else {
      if function.parameters.length() != 2 ||
        policy.user_data >= function.parameters.length() ||
        normalized_type(function.canonical_return_type) != "void" ||
        normalized_type(function.parameters[policy.user_data].canonical_type) !=
        "void*" ||
        normalized_type(shape.return_type) != "void" ||
        shape.parameters.length() != 2 ||
        normalized_type(shape.parameters[0]) != "void*" ||
        normalized_type(shape.parameters[1]) != "int" {
        fail(
          "persistent callback requires void (void*, int) and void* user data: " +
          function.name,
        )
      }
      let unregister = match all.get(policy.unregister) {
        Some(value) => value
        None =>
          fail("unknown callback unregister function: " + policy.unregister)
      }
      if unregister.parameters.length() != 1 ||
        normalized_type(unregister.parameters[0].canonical_type) != "void*" ||
        normalized_type(unregister.canonical_return_type) != "void" ||
        unregister.c_signature.contains("...") {
        fail("callback unregister must be void (void*): " + policy.unregister)
      }
    }
  }
}

///|
fn render_v2_call_callback(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  config : GenerateConfig,
) -> (String?, String?, String) {
  guard config.callback_for(function.name) is Some(policy) else {
    return (None, None, "missing callback policy")
  }
  if policy.lifetime == "persistent" {
    return render_v2_persistent_callback(function, policy)
  }
  let shape = match
    callback_shape(function.parameters[policy.callback].canonical_type) {
    Some(value) => value
    None => return (None, None, "callback parameter is not a function pointer")
  }
  let callback_type = match call_callback_type(shape) {
    Some(value) => value
    None => return (None, None, "unsupported callback ABI")
  }
  let moon_return = match
    callback_direct_type(function.canonical_return_type, result=true) {
    Some(value) => value
    None => return (None, None, "unsupported function return ABI")
  }
  let params : Array[String] = []
  for index, parameter in function.parameters {
    let moon_type = if index == policy.callback {
      callback_type
    } else {
      if v2_abi_kind(parameter.c_type, parameter.canonical_type) != "" {
        return (None, None, "target-dependent callback call parameter")
      }
      match
        resolve_configured_type(
          parameter.c_type,
          parameter.canonical_type,
          aliases,
          opaque_types,
          enums,
          config,
          utf8_input=false,
          result=false,
        ) {
        Some(value) if value.moon_type == "Int" ||
          value.moon_type == "UInt" ||
          value.moon_type == "Float" ||
          value.moon_type == "Double" => value.moon_type
        _ => return (None, None, "unsupported callback call parameter")
      }
    }
    params.push("arg" + index.to_string() + " : " + moon_type)
  }
  let name = function.moon_name
  let line = v2_extern(name, params, moon_return)
    .replace_all(old="extern \"C\"", new="pub extern \"C\"")
    .replace_all(old="\"" + name + "\"", new="\"" + function.symbol + "\"")
  (Some("///|\n" + line), None, "")
}

///|
fn render_v2_persistent_callback(
  function : CFunction,
  policy : CallbackPolicy,
) -> (String?, String?, String) {
  let name = function.moon_name
  let state_type = "MbgRegistration_" + name
  let data_type = "MbgCallbackData_" + name
  let c_state = "mbg_registration_" + name
  let bridge = "mbg_callback_" + name
  let raw_parameters = if policy.callback == 0 {
    "callback : FuncRef[(" +
    data_type +
    ", Int) -> Unit], user_data : " +
    data_type
  } else {
    "user_data : " +
    data_type +
    ", callback : FuncRef[(" +
    data_type +
    ", Int) -> Unit]"
  }
  let moon = "///|\n#external\npub type " +
    data_type +
    "\n\n" +
    "///|\npub extern \"C\" fn " +
    name +
    "_raw(" +
    raw_parameters +
    ") -> Unit = \"" +
    function.symbol +
    "\"\n\n" +
    "///|\npub extern \"C\" fn " +
    name +
    "_unregister_raw(user_data : " +
    data_type +
    ") -> Unit = \"" +
    policy.unregister +
    "\"\n\n" +
    "///|\npub type " +
    state_type +
    "\n\n" +
    "///|\n#borrow(callback)\n" +
    v2_extern(
      bridge,
      [
        "invoke : FuncRef[((Int) -> Unit, Int) -> Unit]", "callback : (Int) -> Unit",
      ],
      state_type,
    ) +
    "\n" +
    "///|\n#borrow(state)\n" +
    v2_extern(bridge + "_close", ["state : " + state_type], "Bool") +
    "\n" +
    "///|\n#borrow(state)\n" +
    v2_extern(bridge + "_active", ["state : " + state_type], "Bool") +
    "\n" +
    "///|\npub fn " +
    name +
    "(callback : (Int) -> Unit) -> " +
    state_type +
    " {\n" +
    "  " +
    bridge +
    "(fn(f, value) { f(value) }, callback)\n}\n\n" +
    "///|\npub fn " +
    state_type +
    "::close(self : " +
    state_type +
    ") -> Bool {\n" +
    "  " +
    bridge +
    "_close(self)\n}\n\n" +
    "///|\npub fn " +
    state_type +
    "::is_closed(self : " +
    state_type +
    ") -> Bool {\n" +
    "  !" +
    bridge +
    "_active(self)\n}\n"
  let register_args = if policy.callback == 0 {
    bridge + "_dispatch, state"
  } else {
    "state, " + bridge + "_dispatch"
  }
  let c = "typedef struct {\n  void (*invoke)(void*, int32_t);\n  void *closure;\n  int32_t active;\n} " +
    c_state +
    ";\n" +
    "static void " +
    bridge +
    "_close_state(" +
    c_state +
    " *state) {\n" +
    "  if (!state->active) return;\n  state->active = 0;\n" +
    "  " +
    policy.unregister +
    "(state);\n" +
    "  void *closure = state->closure;\n  state->closure = NULL;\n" +
    "  moonbit_decref(closure);\n}\n" +
    "static void " +
    bridge +
    "_finalize(void *raw) {\n" +
    "  " +
    bridge +
    "_close_state((" +
    c_state +
    " *)raw);\n}\n" +
    "static void " +
    bridge +
    "_dispatch(void *data, int value) {\n" +
    "  " +
    c_state +
    " *state = (" +
    c_state +
    " *)data;\n" +
    "  if (!state->active) return;\n" +
    "  void *closure = state->closure;\n  moonbit_incref(state);\n" +
    "  moonbit_incref(closure);\n  state->invoke(closure, (int32_t)value);\n" +
    "  moonbit_decref(closure);\n  moonbit_decref(state);\n}\n" +
    "MOONBIT_FFI_EXPORT " +
    c_state +
    " *" +
    bridge +
    "(void (*invoke)(void*, int32_t), void *closure) {\n" +
    "  typedef char mbg_check_int[(sizeof(int) == sizeof(int32_t)) ? 1 : -1];\n" +
    "  " +
    c_state +
    " *state = (" +
    c_state +
    " *)moonbit_make_external_object(" +
    bridge +
    "_finalize, sizeof(" +
    c_state +
    "));\n" +
    "  state->invoke = invoke;\n  state->closure = closure;\n  state->active = 1;\n" +
    "  moonbit_incref(closure);\n  " +
    function.name +
    "(" +
    register_args +
    ");\n" +
    "  return state;\n}\n" +
    "MOONBIT_FFI_EXPORT int32_t " +
    bridge +
    "_close(" +
    c_state +
    " *state) {\n" +
    "  if (!state->active) return 0;\n  " +
    bridge +
    "_close_state(state);\n  return 1;\n}\n" +
    "MOONBIT_FFI_EXPORT int32_t " +
    bridge +
    "_active(" +
    c_state +
    " *state) { return state->active; }\n"
  (Some(moon), Some(c), "")
}
