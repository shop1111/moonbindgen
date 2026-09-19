///|
fn render_function(
  function : CFunction,
  aliases : Map[String, String],
  opaque_types : Map[String, Bool],
  enums : Map[String, Bool],
) -> (String?, String) {
  ignore(function.source.line)
  if function.c_signature.contains("...") {
    return (None, "variadic function")
  }
  let return_m = match
    resolve_type(
      function.return_type,
      aliases,
      opaque_types,
      enums,
      result=true,
    ) {
    Some(value) => value
    None => return (None, "unsupported return type: " + function.return_type)
  }
  let params : Array[String] = []
  for index, parameter in function.parameters {
    ignore(parameter.name)
    let mtype = match
      resolve_type(parameter.c_type, aliases, opaque_types, enums, result=false) {
      Some(value) => value
      None => return (None, "unsupported parameter type: " + parameter.c_type)
    }
    params.push("arg" + index.to_string() + " : " + mtype)
  }
  let declaration = "pub extern \"C\" fn " +
    function.name +
    "(" +
    params.join(", ") +
    ") -> " +
    return_m +
    " = \"" +
    function.symbol +
    "\"\n"
  if params.length() > 2 || (params.length() == 2 && declaration.length() > 105) {
    let body = params.map(param => "  " + param + ",").join("\n")
    let multiline = "///|\npub extern \"C\" fn " +
      function.name +
      "(\n" +
      body +
      "\n) -> " +
      return_m +
      " = \"" +
      function.symbol +
      "\"\n"
    (Some(multiline), "")
  } else {
    (Some("///|\n" + declaration), "")
  }
}
