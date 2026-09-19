///|
fn field(node : Json, name : String) -> Json? {
  match node {
    Json::Object(fields) => fields.get(name)
    _ => None
  }
}

///|
fn text_field(node : Json, name : String) -> String? {
  match field(node, name) {
    Some(Json::String(value)) => Some(value)
    _ => None
  }
}

///|
fn int_field(node : Json, name : String) -> Int? {
  match field(node, name) {
    Some(Json::Number(value, ..)) => Some(value.to_int())
    _ => None
  }
}

///|
fn array_field(node : Json, name : String) -> Array[Json] {
  match field(node, name) {
    Some(Json::Array(items)) => items
    _ => []
  }
}

///|
fn type_spelling(node : Json) -> String? {
  match field(node, "type") {
    Some(ty) => text_field(ty, "qualType")
    None => None
  }
}

///|
fn source_file(node : Json) -> String? {
  match field(node, "loc") {
    Some(loc) => text_field(loc, "file")
    None => None
  }
}

///|
priv struct SourceLocation {
  file : String
  line : Int
}

///|
priv struct LocatedNode {
  node : Json
  source : SourceLocation
}

///|
fn located_nodes(ast : Json) -> Array[LocatedNode] {
  let result : Array[LocatedNode] = []
  let mut current_file = ""
  for node in array_field(ast, "inner") {
    match source_file(node) {
      Some(path) => current_file = path
      None => ()
    }
    let line = match field(node, "loc") {
      Some(loc) => int_field(loc, "line").unwrap_or(0)
      None => 0
    }
    result.push({ node, source: { file: current_file, line } })
  }
  result
}

///|
fn normalized_path(path : String) -> String {
  path.replace_all(old="\\", new="/").to_lower()
}

///|
fn same_header(source : String, header : String) -> Bool {
  let source = normalized_path(source)
  let header = normalized_path(header)
  source == header ||
  header.has_suffix("/" + source) ||
  source.has_suffix("/" + header)
}
