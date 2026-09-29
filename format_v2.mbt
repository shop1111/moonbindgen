///|
fn v2_extern(
  name : String,
  parameters : Array[String],
  return_type : String,
) -> String {
  let line = "extern \"C\" fn " +
    name +
    "(" +
    parameters.join(", ") +
    ") -> " +
    return_type +
    " = \"" +
    name +
    "\"\n"
  if line.length() <= 90 && parameters.length() <= 2 {
    line
  } else {
    "extern \"C\" fn " +
    name +
    "(\n" +
    parameters.map(parameter => "  " + parameter + ",").join("\n") +
    "\n) -> " +
    return_type +
    " = \"" +
    name +
    "\"\n"
  }
}

///|
fn v2_public_head(name : String, parameters : Array[String]) -> String {
  let line = "pub fn " + name + "(" + parameters.join(", ") + ")"
  if line.length() <= 90 && parameters.length() <= 2 {
    line
  } else {
    "pub fn " +
    name +
    "(\n" +
    parameters.map(parameter => "  " + parameter + ",").join("\n") +
    "\n)"
  }
}
