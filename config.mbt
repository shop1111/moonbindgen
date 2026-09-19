///|
pub(all) enum UnsupportedPolicy {
  Report
  Error
} derive(Debug, Eq)

///|
pub struct GenerateConfig {
  include_functions : Map[String, Bool]
  exclude_functions : Map[String, Bool]
  renames : Map[String, String]
  type_overrides : Map[String, String]
  utf8_inputs : Map[String, Bool]
  unsupported_policy : UnsupportedPolicy
}

///|
pub(all) suberror ConfigError {
  InvalidConfig(String)
} derive(Debug, Eq)

///|
pub fn GenerateConfig::default() -> GenerateConfig {
  {
    include_functions: Map([]),
    exclude_functions: Map([]),
    renames: Map([]),
    type_overrides: Map([]),
    utf8_inputs: Map([]),
    unsupported_policy: Report,
  }
}

///|
fn invalid_config(message : String) -> Unit raise ConfigError {
  raise ConfigError::InvalidConfig(message)
}

///|
fn string_set(
  json : Json,
  name : String,
) -> Map[String, Bool] raise ConfigError {
  let result : Map[String, Bool] = Map([])
  match field(json, name) {
    None => ()
    Some(Json::Array(values)) =>
      for value in values {
        match value {
          Json::String(item) => result[item] = true
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
    Some(Json::Object(values)) =>
      for key, value in values {
        match value {
          Json::String(item) => result[key] = item
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
pub fn parse_config(text : String) -> GenerateConfig raise ConfigError {
  let json = @json.parse(text) catch {
    _ => raise ConfigError::InvalidConfig("configuration is not valid JSON")
  }
  let fields = match json {
    Json::Object(values) => values
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
      | "unsupported_policy" => ()
      _ => invalid_config("unknown configuration field: " + key)
    }
  }
  if text_field(json, "schema") != Some("moonbindgen-config-v1") {
    invalid_config("schema must be moonbindgen-config-v1")
  }
  let unsupported_policy = match text_field(json, "unsupported_policy") {
    None | Some("report") => UnsupportedPolicy::Report
    Some("error") => UnsupportedPolicy::Error
    Some(value) => {
      invalid_config(
        "unsupported_policy must be report or error, got: " + value,
      )
      UnsupportedPolicy::Report
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
  {
    include_functions: string_set(json, "include_functions"),
    exclude_functions: string_set(json, "exclude_functions"),
    renames: string_map(json, "renames"),
    type_overrides,
    utf8_inputs: string_set(json, "utf8_inputs"),
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
