///|
/// Controls how generation handles declarations outside MoonBindgen's
/// conservative ABI surface.
pub(all) enum UnsupportedPolicy {
  /// Keep supported declarations and record unsupported ones in the report.
  Report
  /// Reject the complete generation when any unsupported declaration is found.
  Error
} derive(Debug, Eq)

///|
#deprecated
pub extend UnsupportedPolicy with Eq::{equal, not_equal}

///|
#deprecated
pub extend UnsupportedPolicy with @debug.Debug::{to_repr}

///|
/// Versioned generation settings parsed from `moonbindgen-config-v1` JSON.
///
/// Use `GenerateConfig::default` for report-only generation, or `parse_config`
/// when loading a user-supplied configuration file.
pub struct GenerateConfig {
  schema_version : Int
  include_functions : Map[String, Bool]
  exclude_functions : Map[String, Bool]
  renames : Map[String, String]
  type_overrides : Map[String, String]
  utf8_inputs : Map[String, Bool]
  output_params : Map[String, Bool]
  null_inputs : Map[String, Bool]
  utf8_borrowed_returns : Map[String, Bool]
  utf8_owned_returns : Map[String, String]
  unsupported_policy : UnsupportedPolicy
  buffers : Array[BufferPolicy]
  return_buffers : Array[ReturnBufferPolicy]
}

///|
/// A position-based byte buffer policy for a config-v2 C function.
pub struct BufferPolicy {
  function_name : String
  pointer : Int
  length : Int
  direction : String
  retention : String
  copy_parameter : Int
  copy_symbol : String
}

///|
/// A borrowed pointer return copied before its owner can be changed.
pub struct ReturnBufferPolicy {
  function_name : String
  length_function : String
  length_args : Array[Int]
  null_function : String
  null_symbol : String
}

///|
/// An error raised when generation configuration is malformed or unsupported.
pub(all) suberror ConfigError {
  /// Carries a stable, user-facing validation message.
  InvalidConfig(String)
} derive(Debug, Eq)

///|
#deprecated
pub extend ConfigError with Eq::{equal, not_equal}

///|
#deprecated
pub extend ConfigError with @debug.Debug::{to_repr}

///|
/// Returns the default configuration with no filters or overrides and with
/// unsupported declarations reported instead of rejected.
pub fn GenerateConfig::default() -> GenerateConfig {
  {
    schema_version: 1,
    include_functions: Map([]),
    exclude_functions: Map([]),
    renames: Map([]),
    type_overrides: Map([]),
    utf8_inputs: Map([]),
    output_params: Map([]),
    null_inputs: Map([]),
    utf8_borrowed_returns: Map([]),
    utf8_owned_returns: Map([]),
    unsupported_policy: Report,
    buffers: [],
    return_buffers: [],
  }
}

///|
fn invalid_config(message : String) -> Unit raise ConfigError {
  raise InvalidConfig(message)
}

///|
fn string_set(
  json : Json,
  name : String,
) -> Map[String, Bool] raise ConfigError {
  let result : Map[String, Bool] = Map([])
  match field(json, name) {
    None => ()
    Some(Array(values)) =>
      for value in values {
        match value {
          String(item) => result[item] = true
          _ => invalid_config(name + " must contain only strings")
        }
      }
    _ => invalid_config(name + " must be an array")
  }
  result
}

///|
fn string_map(
  json : Json,
  name : String,
) -> Map[String, String] raise ConfigError {
  let result : Map[String, String] = Map([])
  match field(json, name) {
    None => ()
    Some(Object(values)) =>
      for key, value in values {
        match value {
          String(item) => result[key] = item
          _ => invalid_config(name + " values must be strings")
        }
      }
    _ => invalid_config(name + " must be an object")
  }
  result
}

///|
fn valid_type_override(name : String) -> Bool {
  match name {
    "Bool"
    | "Byte"
    | "Int"
    | "UInt"
    | "Int64"
    | "UInt64"
    | "Float"
    | "Double" => true
    _ => false
  }
}

///|
fn valid_c_identifier(name : String) -> Bool {
  if name == "" {
    return false
  }
  let mut first = true
  for char in name {
    if first && !(char.is_ascii_alphabetic() || char == '_') {
      return false
    }
    if !(char.is_ascii_alphabetic() || char.is_ascii_digit() || char == '_') {
      return false
    }
    first = false
  }
  true
}

///|
fn required_string(json : Json, name : String) -> String raise ConfigError {
  match text_field(json, name) {
    Some(value) if value != "" => value
    _ => {
      invalid_config(name + " must be a nonempty string")
      ""
    }
  }
}

///|
fn required_index(json : Json, name : String) -> Int raise ConfigError {
  match field(json, name) {
    Some(Number(number, ..)) if number >= 0.0 &&
      number == number.to_int().to_double() => number.to_int()
    _ => {
      invalid_config(name + " must be a nonnegative integer")
      -1
    }
  }
}

///|
fn optional_string(json : Json, name : String) -> String raise ConfigError {
  match field(json, name) {
    None => ""
    Some(String(value)) => value
    _ => {
      invalid_config(name + " must be a string")
      ""
    }
  }
}

///|
fn parse_buffers(json : Json) -> Array[BufferPolicy] raise ConfigError {
  let result : Array[BufferPolicy] = []
  let values = match field(json, "buffers") {
    None => return result
    Some(Array(items)) => items
    _ => {
      invalid_config("buffers must be an array")
      return result
    }
  }
  for item in values {
    guard item is Object(fields) else {
      invalid_config("buffers entries must be objects")
      continue
    }
    for key, _ in fields {
      match key {
        "function"
        | "pointer"
        | "length"
        | "direction"
        | "retention"
        | "copy_parameter"
        | "copy_symbol" => ()
        _ => invalid_config("unknown buffer field: " + key)
      }
    }
    let function_name = required_string(item, "function")
    let pointer = required_index(item, "pointer")
    let length = required_index(item, "length")
    let direction = required_string(item, "direction")
    let retention = match field(item, "retention") {
      None => "call"
      Some(String(value)) => value
      _ => {
        invalid_config("retention must be a string")
        "call"
      }
    }
    let copy_parameter = match field(item, "copy_parameter") {
      None => -1
      Some(_) => required_index(item, "copy_parameter")
    }
    let copy_symbol = optional_string(item, "copy_symbol")
    if pointer == length {
      invalid_config("buffer pointer and length must differ: " + function_name)
    }
    if copy_parameter == pointer || copy_parameter == length {
      invalid_config("copy parameter conflicts with buffer: " + function_name)
    }
    if direction != "in" && direction != "out" {
      invalid_config("buffer direction must be in or out: " + function_name)
    }
    if retention != "call" && retention != "copy" {
      invalid_config("buffer retention must be call or copy: " + function_name)
    }
    if direction == "out" && retention != "call" {
      invalid_config("output buffers must use call retention: " + function_name)
    }
    if (copy_parameter >= 0) != (copy_symbol != "") ||
      (
        copy_parameter >= 0 &&
        (
          direction != "in" ||
          retention != "copy" ||
          !valid_c_identifier(copy_symbol)
        )
      ) {
      invalid_config("invalid copy token for buffer: " + function_name)
    }
    for previous in result {
      if previous.function_name == function_name {
        invalid_config("only one buffer policy per function: " + function_name)
      }
    }
    result.push({
      function_name,
      pointer,
      length,
      direction,
      retention,
      copy_parameter,
      copy_symbol,
    })
  }
  result
}

///|
fn parse_return_buffers(
  json : Json,
) -> Array[ReturnBufferPolicy] raise ConfigError {
  let result : Array[ReturnBufferPolicy] = []
  let values = match field(json, "return_buffers") {
    None => return result
    Some(Array(items)) => items
    _ => {
      invalid_config("return_buffers must be an array")
      return result
    }
  }
  for item in values {
    guard item is Object(fields) else {
      invalid_config("return_buffers entries must be objects")
      continue
    }
    for key, _ in fields {
      match key {
        "function"
        | "length_function"
        | "length_args"
        | "null_function"
        | "null_symbol" => ()
        _ => invalid_config("unknown return buffer field: " + key)
      }
    }
    let function_name = required_string(item, "function")
    let length_function = required_string(item, "length_function")
    let length_args : Array[Int] = []
    match field(item, "length_args") {
      Some(Array(items)) =>
        for arg in items {
          match arg {
            Number(number, ..) if number >= 0.0 &&
              number == number.to_int().to_double() =>
              length_args.push(number.to_int())
            _ => invalid_config("length_args must be nonnegative integers")
          }
        }
      _ => invalid_config("length_args must be an array")
    }
    let null_function = optional_string(item, "null_function")
    let null_symbol = optional_string(item, "null_symbol")
    if (null_function == "") != (null_symbol == "") ||
      (null_symbol != "" && !valid_c_identifier(null_symbol)) {
      invalid_config("invalid null discriminator: " + function_name)
    }
    for previous in result {
      if previous.function_name == function_name {
        invalid_config("duplicate return buffer: " + function_name)
      }
    }
    result.push({
      function_name,
      length_function,
      length_args,
      null_function,
      null_symbol,
    })
  }
  result
}

///|
/// Parses and validates a `moonbindgen-config-v1` JSON document.
///
/// Unknown fields, unsafe type overrides, and schema mismatches raise
/// `ConfigError::InvalidConfig`.
pub fn parse_config(text : String) -> GenerateConfig raise ConfigError {
  let json = @json.parse(text) catch {
    _ => raise InvalidConfig("configuration is not valid JSON")
  }
  let fields = match json {
    Object(values) => values
    _ => {
      invalid_config("configuration root must be an object")
      return GenerateConfig::default()
    }
  }
  for key, _ in fields {
    match key {
      "schema"
      | "include_functions"
      | "exclude_functions"
      | "renames"
      | "type_overrides"
      | "utf8_inputs"
      | "output_params"
      | "null_inputs"
      | "utf8_borrowed_returns"
      | "utf8_owned_returns"
      | "unsupported_policy"
      | "buffers"
      | "return_buffers" => ()
      _ => invalid_config("unknown configuration field: " + key)
    }
  }
  let schema_version = match text_field(json, "schema") {
    Some("moonbindgen-config-v1") => 1
    Some("moonbindgen-config-v2") => 2
    _ => {
      invalid_config(
        "schema must be moonbindgen-config-v1 or moonbindgen-config-v2",
      )
      1
    }
  }
  if schema_version == 1 &&
    (
      field(json, "buffers") is Some(_) ||
      field(json, "return_buffers") is Some(_)
    ) {
    invalid_config("buffer policies require moonbindgen-config-v2")
  }
  let unsupported_policy = match text_field(json, "unsupported_policy") {
    None | Some("report") => Report
    Some("error") => Error
    Some(value) => {
      invalid_config(
        "unsupported_policy must be report or error, got: " + value,
      )
      Report
    }
  }
  let type_overrides = string_map(json, "type_overrides")
  if schema_version == 2 && type_overrides.length() > 0 {
    invalid_config("type_overrides are not permitted in config-v2")
  }
  for c_type, moon_type in type_overrides {
    if !valid_type_override(moon_type) {
      invalid_config(
        "type_overrides[" + c_type + "] is not a supported C ABI type",
      )
    }
  }
  let output_params = string_set(json, "output_params")
  let null_inputs = string_set(json, "null_inputs")
  let utf8_borrowed_returns = string_set(json, "utf8_borrowed_returns")
  let utf8_owned_returns = string_map(json, "utf8_owned_returns")
  for name, free_fn in utf8_owned_returns {
    if !valid_c_identifier(free_fn) {
      invalid_config("utf8_owned_returns[" + name + "] needs a C function name")
    }
    if utf8_borrowed_returns.contains(name) {
      invalid_config("return string ownership conflicts for: " + name)
    }
  }
  for key, _ in output_params {
    if null_inputs.contains(key) {
      invalid_config("output_params and null_inputs conflict for: " + key)
    }
  }
  {
    schema_version,
    include_functions: string_set(json, "include_functions"),
    exclude_functions: string_set(json, "exclude_functions"),
    renames: string_map(json, "renames"),
    type_overrides,
    utf8_inputs: string_set(json, "utf8_inputs"),
    output_params,
    null_inputs,
    utf8_borrowed_returns,
    utf8_owned_returns,
    unsupported_policy,
    buffers: parse_buffers(json),
    return_buffers: parse_return_buffers(json),
  }
}

///|
fn GenerateConfig::allows(self : GenerateConfig, name : String) -> Bool {
  (
    self.include_functions.length() == 0 ||
    self.include_functions.contains(name)
  ) &&
  !self.exclude_functions.contains(name)
}

///|
fn GenerateConfig::renamed(self : GenerateConfig, name : String) -> String {
  self.renames.get(name).unwrap_or(name)
}

///|
fn GenerateConfig::type_override(
  self : GenerateConfig,
  raw : String,
  canonical : String,
) -> String? {
  match self.type_overrides.get(raw) {
    Some(value) => Some(value)
    None => self.type_overrides.get(canonical)
  }
}

///|
fn GenerateConfig::is_utf8_input(
  self : GenerateConfig,
  function_name : String,
  parameter_name : String,
) -> Bool {
  self.utf8_inputs.contains(function_name + "." + parameter_name)
}

///|
fn GenerateConfig::is_output(
  self : GenerateConfig,
  function_name : String,
  parameter_name : String,
) -> Bool {
  self.output_params.contains(function_name + "." + parameter_name)
}

///|
fn GenerateConfig::is_null_input(
  self : GenerateConfig,
  function_name : String,
  parameter_name : String,
) -> Bool {
  self.null_inputs.contains(function_name + "." + parameter_name)
}

///|
fn GenerateConfig::has_bridge(self : GenerateConfig, name : String) -> Bool {
  if self.utf8_borrowed_returns.contains(name) ||
    self.utf8_owned_returns.contains(name) {
    return true
  }
  for key, _ in self.output_params {
    if key.has_prefix(name + ".") {
      return true
    }
  }
  for policy in self.buffers {
    if policy.function_name == name {
      return true
    }
  }
  for policy in self.return_buffers {
    if policy.function_name == name {
      return true
    }
  }
  false
}

///|
fn GenerateConfig::buffer_for(
  self : GenerateConfig,
  name : String,
) -> BufferPolicy? {
  for policy in self.buffers {
    if policy.function_name == name {
      return Some(policy)
    }
  }
  None
}

///|
fn GenerateConfig::return_buffer_for(
  self : GenerateConfig,
  name : String,
) -> ReturnBufferPolicy? {
  for policy in self.return_buffers {
    if policy.function_name == name {
      return Some(policy)
    }
  }
  None
}
