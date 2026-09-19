///|
pub struct GenerateResult {
  bindings : String
  report : String
  generated : Int
  skipped : Int
}

///|
fn report_item(name : String, status : String, reason : String) -> Json {
  Json::object({
    "name": Json::string(name),
    "status": Json::string(status),
    "reason": Json::string(reason),
  })
}

///|
fn enum_number(node : Json) -> Int? {
  for child in array_field(node, "inner") {
    match text_field(child, "value") {
      Some(value) => {
        let number = @string.parse_int(value) catch { _ => return None }
        return Some(number)
      }
      None => ()
    }
  }
  None
}

///|
pub fn generate(ast_text : String, header : String) -> GenerateResult raise {
  let ast = @json.parse(ast_text)
  if text_field(ast, "kind") != Some("TranslationUnitDecl") {
    fail("Clang output is not a translation unit")
  }
  let aliases : Map[String, String] = Map([])
  let opaque_types : Map[String, Bool] = Map([])
  let enums : Map[String, Bool] = Map([])
  let enum_lines : Array[String] = []
  let enum_reports : Array[Json] = []
  let nodes = array_field(ast, "inner")
  let mut current_file = ""
  for node in nodes {
    match source_file(node) {
      Some(path) => current_file = path
      None => ()
    }
    let on_header = same_header(current_file, header)
    match text_field(node, "kind") {
      Some("TypedefDecl") =>
        match (text_field(node, "name"), type_spelling(node)) {
          (Some(name), Some(ctype)) =>
            if ctype.has_prefix("struct ") {
              let tag = ctype[7:].to_owned()
              if name == tag {
                opaque_types[name] = true
              } else {
                aliases[name] = ctype
              }
            } else {
              aliases[name] = ctype
            }
          _ => ()
        }
      Some("EnumDecl") => {
        let mut current = -1
        let mut valid = true
        let lines : Array[String] = []
        for constant in array_field(node, "inner") {
          if text_field(constant, "kind") == Some("EnumConstantDecl") {
            let value = if array_field(constant, "inner").length() > 0 {
              enum_number(constant)
            } else if current < 2147483647 {
              Some(current + 1)
            } else {
              None
            }
            match (text_field(constant, "name"), value) {
              (Some(name), Some(number)) => {
                current = number
                lines.push(
                  "///|\npub let c_" +
                  name.to_lower() +
                  " : Int = " +
                  number.to_string() +
                  "\n",
                )
              }
              _ => valid = false
            }
          }
        }
        let enum_name = match text_field(node, "name") {
          Some(name) => name
          None => "<anonymous>"
        }
        if valid {
          if enum_name != "<anonymous>" {
            enums[enum_name] = true
          }
          if on_header {
            for line in lines {
              enum_lines.push(line)
            }
            enum_reports.push(report_item(enum_name, "generated", ""))
          }
        } else if on_header {
          enum_reports.push(
            report_item(
              enum_name, "skipped", "enum value outside supported Int range",
            ),
          )
        }
      }
      _ => ()
    }
  }
  let function_lines : Array[String] = []
  let items : Array[Json] = []
  let seen : Map[String, Bool] = Map([])
  let mut generated = 0
  let mut skipped = 0
  current_file = ""
  for node in nodes {
    match source_file(node) {
      Some(path) => current_file = path
      None => ()
    }
    if !same_header(current_file, header) ||
      text_field(node, "kind") != Some("FunctionDecl") {
      continue
    }
    if text_field(node, "name") is None || type_spelling(node) is None {
      fail("Unrecognized Clang FunctionDecl structure")
    }
    for child in array_field(node, "inner") {
      if text_field(child, "kind") == Some("ParmVarDecl") &&
        type_spelling(child) is None {
        fail("Unrecognized Clang ParmVarDecl structure")
      }
    }
    let name = match text_field(node, "name") {
      Some(value) => value
      None => "<unnamed>"
    }
    if seen.contains(name) {
      skipped += 1
      items.push(report_item(name, "skipped", "duplicate declaration"))
      continue
    }
    seen[name] = true
    let function = match c_function(node) {
      Some(value) => value
      None => fail("Unrecognized Clang FunctionDecl structure")
    }
    let (rendered, reason) = render_function(
      function, aliases, opaque_types, enums,
    )
    match rendered {
      Some(code) => {
        function_lines.push(code)
        generated += 1
        items.push(report_item(name, "generated", ""))
      }
      None => {
        skipped += 1
        items.push(report_item(name, "skipped", reason))
      }
    }
  }
  let declarations : Array[String] = [
    "// Generated by MoonBindgen. C resources require manual lifetime management.\n",
  ]
  let function_text = function_lines.join("\n")
  for pair in opaque_types {
    let (name, _) = pair
    if function_text.contains("C_" + name) {
      declarations.push("///|\n#external\npub type C_" + name + "\n")
    }
  }
  for line in enum_lines {
    declarations.push(line)
  }
  declarations.push(function_text)
  let path_parts = normalized_path(header).split("/").to_array()
  let report = Json::object({
    "schema": Json::string("moonbindgen-report-v1"),
    "header": Json::string(path_parts[path_parts.length() - 1].to_owned()),
    "generated": Json::number(generated.to_double()),
    "skipped": Json::number(skipped.to_double()),
    "functions": Json::array(items),
    "enums": Json::array(enum_reports),
  }).stringify(indent=2)
  { bindings: declarations.join("\n"), report, generated, skipped }
}
