///|
priv struct CParameter {
  name : String
  c_type : String
  canonical_type : String
}

///|
priv struct CFunction {
  name : String
  moon_name : String
  symbol : String
  c_signature : String
  return_type : String
  canonical_return_type : String
  parameters : Array[CParameter]
  source : SourceLocation
}

///|
fn function_return(signature : String) -> String? {
  let parts = signature.split(" (").to_array()
  if parts.length() < 2 {
    None
  } else {
    Some(parts[0].to_owned())
  }
}

///|
fn c_function(node : Json, source : SourceLocation) -> CFunction? {
  let name = match text_field(node, "name") {
    Some(value) => value
    None => return None
  }
  let signature = match type_spelling(node) {
    Some(value) => value
    None => return None
  }
  let return_type = match function_return(signature) {
    Some(value) => value
    None => return None
  }
  let canonical_signature = canonical_type_spelling(node).unwrap_or(signature)
  let canonical_return_type = function_return(canonical_signature).unwrap_or(
    return_type,
  )
  let parameters : Array[CParameter] = []
  let mut index = 0
  for child in array_field(node, "inner") {
    if text_field(child, "kind") == Some("ParmVarDecl") {
      let c_type = match type_spelling(child) {
        Some(value) => value
        None => return None
      }
      let canonical_type = canonical_type_spelling(child).unwrap_or(c_type)
      let name = match text_field(child, "name") {
        Some(value) => value
        None => "arg" + index.to_string()
      }
      parameters.push({ name, c_type, canonical_type })
      index += 1
    }
  }
  let symbol = match text_field(node, "mangledName") {
    Some(value) => value
    None => name
  }
  Some({
    name,
    moon_name: moonbit_value_name(name),
    symbol,
    c_signature: signature,
    return_type,
    canonical_return_type,
    parameters,
    source,
  })
}

///|
fn CFunction::with_moon_name(self : CFunction, name : String) -> CFunction {
  {
    name: self.name,
    moon_name: moonbit_value_name(name),
    symbol: self.symbol,
    c_signature: self.c_signature,
    return_type: self.return_type,
    canonical_return_type: self.canonical_return_type,
    parameters: self.parameters,
    source: self.source,
  }
}
