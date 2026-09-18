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
