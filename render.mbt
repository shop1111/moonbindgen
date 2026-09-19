///|
fn render_function(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
  config : GenerateConfig,
) -> (String?, String) {
  ignore(function.source.line)
  if function.c_signature.contains("...") {
    return (None, "variadic function")
  }
  let return_m = match
    resolve_configured_type(
      function.return_type,
      function.canonical_return_type,
      aliases,
      opaque_types,
      enums,
      config,
      utf8_input=false,
      result=true,
    ) {
    Some(value) => value.moon_type
    None => return (None, "unsupported return type: " + function.return_type)
  }
  let params : Array[String] = []
  let borrowed : Array[String] = []
  let parameter_names : Map[String, Int] = Map([])
  for parameter in function.parameters {
    let resolved = match
      resolve_configured_type(
        parameter.c_type,
        parameter.canonical_type,
        aliases,
        opaque_types,
        enums,
        config,
        utf8_input=config.is_utf8_input(function.name, parameter.name),
        result=false,
      ) {
      Some(value) => value
      None => return (None, "unsupported parameter type: " + parameter.c_type)
    }
    let base_name = moonbit_value_name(parameter.name)
    let count = parameter_names.get(base_name).unwrap_or(0) + 1
    parameter_names[base_name] = count
    let name = if count == 1 {
      base_name
    } else {
      base_name + "_" + count.to_string()
    }
    if resolved.borrowed {
      borrowed.push(name)
    }
    params.push(name + " : " + resolved.moon_type)
  }
  let attributes = if borrowed.length() == 0 {
    ""
  } else {
    "#borrow(" + borrowed.join(", ") + ")\n"
  }
  let declaration = "pub extern \"C\" fn " +
    function.moon_name +
    "(" +
    params.join(", ") +
    ") -> " +
    return_m +
    " = \"" +
    function.symbol +
    "\"\n"
  if params.length() > 2 || (params.length() == 2 && declaration.length() > 105) {
    let body = params.map(param => "  " + param + ",").join("\n")
    let multiline = "///|\n" +
      attributes +
      "pub extern \"C\" fn " +
      function.moon_name +
      "(\n" +
      body +
      "\n) -> " +
      return_m +
      " = \"" +
      function.symbol +
      "\"\n"
    (Some(multiline), "")
  } else {
    (Some("///|\n" + attributes + declaration), "")
  }
}
