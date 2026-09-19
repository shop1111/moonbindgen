///|
fn normalized_type(raw : String) -> String {
  let mut ctype = raw
    .trim()
    .to_owned()
    .replace_all(old="  ", new=" ")
    .replace_all(old=" *", new="*")
  if ctype.has_prefix("const ") {
    ctype = ctype[6:].to_owned()
  }
  if ctype.has_prefix("volatile ") {
    ctype = ctype[9:].to_owned()
  }
  ctype
}

///|
priv struct ResolvedType {
  moon_type : String
  borrowed : Bool
}

///|
fn resolve_type(
  raw : String,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  result~ : Bool,
) -> String? {
  let mut ctype = normalized_type(raw)
  for _ in 0..<16 {
    match aliases.get(ctype) {
      Some(next) => ctype = normalized_type(next)
      None => break
    }
  }
  match ctype {
    "void" => if result { Some("Unit") } else { None }
    "char" | "signed char" | "unsigned char" => Some("Byte")
    "int" | "signed int" => Some("Int")
    "unsigned int" => Some("UInt")
    "float" => Some("Float")
    "double" => Some("Double")
    "long long" | "long long int" | "signed long long" => Some("Int64")
    "unsigned long long" | "unsigned long long int" => Some("UInt64")
    _ =>
      if ctype.has_prefix("enum ") && enums.contains(ctype[5:].to_owned()) {
        Some("Int")
      } else if ctype.has_suffix("*") {
        let mut base = ctype[:ctype.length() - 1].trim().to_owned()
        if base.has_prefix("const ") {
          base = base[6:].to_owned()
        }
        if base.has_prefix("struct ") {
          base = base[7:].to_owned()
        }
        if opaque_types.contains(base) {
          Some(opaque_type_name(base))
        } else {
          None
        }
      } else if enums.contains(ctype) {
        Some("Int")
      } else {
        None
      }
  }
}

///|
fn resolve_configured_type(
  raw : String,
  canonical : String,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  config : GenerateConfig,
  utf8_input~ : Bool,
  result~ : Bool,
) -> ResolvedType? {
  match config.type_override(raw, canonical) {
    Some(moon_type) => return Some({ moon_type, borrowed: false })
    None => ()
  }
  if utf8_input {
    if normalized_type(raw) == "char*" || normalized_type(canonical) == "char*" {
      return Some({ moon_type: "Bytes", borrowed: true })
    }
    return None
  }
  let source = if canonical == "" { raw } else { canonical }
  match resolve_type(source, aliases, opaque_types, enums, result~) {
    Some(moon_type) => Some({ moon_type, borrowed: false })
    None => None
  }
}
