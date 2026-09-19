///|
priv struct CParameter {
  name : String
  c_type : String
}

///|
priv struct CFunction {
  name : String
  symbol : String
  c_signature : String
  return_type : String
  parameters : Array[CParameter]
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
fn c_function(node : Json) -> CFunction? {
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
  let parameters : Array[CParameter] = []
  let mut index = 0
  for child in array_field(node, "inner") {
    if text_field(child, "kind") == Some("ParmVarDecl") {
      let c_type = match type_spelling(child) {
        Some(value) => value
        None => return None
      }
      let name = match text_field(child, "name") {
        Some(value) => value
        None => "arg" + index.to_string()
      }
      parameters.push({ name, c_type })
      index += 1
    }
  }
  let symbol = match text_field(node, "mangledName") {
    Some(value) => value
    None => name
  }
  Some({ name, symbol, c_signature: signature, return_type, parameters })
}
