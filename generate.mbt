///|
pub struct GenerateResult {
  bindings : String
  report : String
  generated : Int
  skipped : Int
}

///|
pub struct ToolMetadata {
  clang_version : String
  clang_target : String
}

///|
pub fn ToolMetadata::new(
  clang_version : String,
  clang_target : String,
) -> ToolMetadata {
  { clang_version, clang_target }
}

///|
pub fn ToolMetadata::unknown() -> ToolMetadata {
  { clang_version: "unknown", clang_target: "unknown" }
}

///|
fn reason_code(status : String, reason : String) -> String {
  if status == "generated" {
    "generated"
  } else if reason == "filtered by configuration" {
    "filtered"
  } else if reason == "duplicate declaration" {
    "duplicate_declaration"
  } else if reason.contains("name collision") {
    "name_collision"
  } else if reason == "variadic function" {
    "variadic_function"
  } else if reason.contains("unsupported return type") {
    "unsupported_return_type"
  } else if reason.contains("unsupported parameter type") {
    "unsupported_parameter_type"
  } else if reason.contains("enum value outside") {
    "enum_value_out_of_range"
  } else {
    "unsupported_declaration"
  }
}

///|
fn report_item(
  kind : String,
  name : String,
  moon_name : String,
  source : SourceLocation,
  c_signature : String,
  moonbit_signature : String,
  status : String,
  reason : String,
) -> Json {
  Json::object({
    "kind": Json::string(kind),
    "c_name": Json::string(name),
    "moonbit_name": Json::string(moon_name),
    "source": Json::object({
      "file": Json::string(source.file),
      "line": Json::number(source.line.to_double()),
    }),
    "c_signature": Json::string(c_signature),
    "moonbit_signature": Json::string(moonbit_signature),
    "status": Json::string(status),
    "reason_code": Json::string(reason_code(status, reason)),
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
  generate_with_metadata(
    ast_text,
    header,
    GenerateConfig::default(),
    ToolMetadata::unknown(),
  )
}

///|
pub fn generate_with_config(
  ast_text : String,
  header : String,
  config : GenerateConfig,
) -> GenerateResult raise {
  generate_with_metadata(ast_text, header, config, ToolMetadata::unknown())
}

///|
pub fn generate_with_metadata(
  ast_text : String,
  header : String,
  config : GenerateConfig,
  metadata : ToolMetadata,
) -> GenerateResult raise {
  let ast = @json.parse(ast_text)
  if text_field(ast, "kind") != Some("TranslationUnitDecl") {
    fail("Clang output is not a translation unit")
  }
  let aliases : Map[String, String] = Map([])
  let opaque_types : Map[String, Bool] = Map([])
  let enums : Map[String, Bool] = Map([])
  let value_names : Map[String, String] = Map([])
  let enum_lines : Array[String] = []
  let enum_reports : Array[Json] = []
  let mut enum_generated = 0
  let mut enum_skipped = 0
  let mut unsupported = 0
  let nodes = located_nodes(ast)
  for entry in nodes {
    let node = entry.node
    let on_header = same_header(entry.source.file, header)
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
                let output_name = "c_" + moonbit_value_name(name)
                if on_header {
                  match value_names.get(output_name) {
                    Some(previous) if previous != name => valid = false
                    _ => value_names[output_name] = name
                  }
                }
                lines.push(
                  "///|\npub let " +
                  output_name +
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
            enum_generated += 1
            enum_reports.push(
              report_item(
                "enum",
                enum_name,
                moonbit_value_name(enum_name),
                entry.source,
                "enum " + enum_name,
                lines.join("\n"),
                "generated",
                "",
              ),
            )
          }
        } else if on_header {
          enum_skipped += 1
          unsupported += 1
          enum_reports.push(
            report_item(
              "enum",
              enum_name,
              moonbit_value_name(enum_name),
              entry.source,
              "enum " + enum_name,
              "",
              "skipped",
              "enum value outside supported Int range",
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
  for entry in nodes {
    let node = entry.node
    if !same_header(entry.source.file, header) ||
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
    if !config.allows(name) {
      skipped += 1
      items.push(
        report_item(
          "function",
          name,
          moonbit_value_name(config.renamed(name)),
          entry.source,
          type_spelling(node).unwrap_or(""),
          "",
          "skipped",
          "filtered by configuration",
        ),
      )
      continue
    }
    if seen.contains(name) {
      skipped += 1
      items.push(
        report_item(
          "function",
          name,
          moonbit_value_name(config.renamed(name)),
          entry.source,
          type_spelling(node).unwrap_or(""),
          "",
          "skipped",
          "duplicate declaration",
        ),
      )
      continue
    }
    seen[name] = true
    let function = match c_function(node, entry.source) {
      Some(value) => value
      None => fail("Unrecognized Clang FunctionDecl structure")
    }
    let function = function.with_moon_name(config.renamed(name))
    match value_names.get(function.moon_name) {
      Some(previous) if previous != function.name => {
        skipped += 1
        unsupported += 1
        items.push(
          report_item(
            "function",
            function.name,
            function.moon_name,
            function.source,
            function.c_signature,
            "",
            "skipped",
            "MoonBit name collision with: " + previous,
          ),
        )
        continue
      }
      _ => value_names[function.moon_name] = function.name
    }
    let (rendered, reason) = render_function(
      function, aliases, opaque_types, enums, config,
    )
    match rendered {
      Some(code) => {
        function_lines.push(code)
        generated += 1
        items.push(
          report_item(
            "function",
            function.name,
            function.moon_name,
            function.source,
            function.c_signature,
            code.trim().to_owned(),
            "generated",
            "",
          ),
        )
      }
      None => {
        skipped += 1
        unsupported += 1
        items.push(
          report_item(
            "function",
            function.name,
            function.moon_name,
            function.source,
            function.c_signature,
            "",
            "skipped",
            reason,
          ),
        )
      }
    }
  }
  let declarations : Array[String] = [
    "// Generated by MoonBindgen. C resources require manual lifetime management.\n",
  ]
  let function_text = function_lines.join("\n")
  let type_names : Map[String, String] = Map([])
  for pair in opaque_types {
    let (name, _) = pair
    let output_name = opaque_type_name(name)
    if function_text.contains(output_name) {
      match type_names.get(output_name) {
        Some(previous) if previous != name =>
          fail("Opaque type name collision: " + previous + " and " + name)
        _ => type_names[output_name] = name
      }
      declarations.push("///|\n#external\npub type " + output_name + "\n")
    }
  }
  for line in enum_lines {
    declarations.push(line)
  }
  declarations.push(function_text)
  if config.unsupported_policy == UnsupportedPolicy::Error && unsupported > 0 {
    fail(
      "generation rejected " +
      unsupported.to_string() +
      " unsupported declarations",
    )
  }
  let path_parts = normalized_path(header).split("/").to_array()
  let included_seen : Map[String, Bool] = Map([])
  let included_files : Array[Json] = []
  for entry in nodes {
    let source = normalized_path(entry.source.file)
    if source != "" &&
      !same_header(source, header) &&
      !included_seen.contains(source) {
      included_seen[source] = true
      included_files.push(Json::string(source))
    }
  }
  let declaration_reports : Array[Json] = []
  for item in enum_reports {
    declaration_reports.push(item)
  }
  for item in items {
    declaration_reports.push(item)
  }
  let report = Json::object({
    "schema": Json::string("moonbindgen-report-v2"),
    "header": Json::string(path_parts[path_parts.length() - 1].to_owned()),
    "clang": Json::object({
      "version": Json::string(metadata.clang_version),
      "target": Json::string(metadata.clang_target),
    }),
    "included_files": Json::array(included_files),
    "generated": Json::number(generated.to_double()),
    "skipped": Json::number(skipped.to_double()),
    "summary": Json::object({
      "functions_generated": Json::number(generated.to_double()),
      "functions_skipped": Json::number(skipped.to_double()),
      "enums_generated": Json::number(enum_generated.to_double()),
      "enums_skipped": Json::number(enum_skipped.to_double()),
      "unsupported": Json::number(unsupported.to_double()),
    }),
    "declarations": Json::array(declaration_reports),
    "functions": Json::array(items),
    "enums": Json::array(enum_reports),
  }).stringify(indent=2)
  { bindings: declarations.join("\n"), report, generated, skipped }
}
