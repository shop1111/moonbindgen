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
      | "unsupported_policy" => ()
      _ => invalid_config("unknown configuration field: " + key)
    }
  }
  if text_field(json, "schema") != Some("moonbindgen-config-v1") {
    invalid_config("schema must be moonbindgen-config-v1")
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
  false
}
