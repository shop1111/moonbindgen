///|
fn is_moonbit_keyword(name : String) -> Bool {
  match name {
    "as"
    | "async"
    | "break"
    | "catch"
    | "const"
    | "continue"
    | "derive"
    | "else"
    | "enum"
    | "extern"
    | "fn"
    | "for"
    | "guard"
    | "if"
    | "impl"
    | "in"
    | "let"
    | "loop"
    | "match"
    | "mut"
    | "noraise"
    | "priv"
    | "pub"
    | "raise"
    | "return"
    | "self"
    | "struct"
    | "test"
    | "trait"
    | "try"
    | "type"
    | "using"
    | "while"
    | "with" => true
    _ => false
  }
}

///|
fn moonbit_value_name(raw : String) -> String {
  let builder = StringBuilder()
  for char in raw {
    if char.is_ascii_alphabetic() {
      builder.write_char(char.to_ascii_lowercase())
    } else if char.is_ascii_digit() || char == '_' {
      builder.write_char(char)
    } else {
      builder.write_char('_')
    }
  }
  let mut result = builder.to_string()
  if result == "" {
    result = "c_value"
  } else if result[0] >= '0' && result[0] <= '9' {
    result = "c_" + result
  }
  if is_moonbit_keyword(result) {
    "c_" + result
  } else {
    result
  }
}

///|
fn opaque_type_name(raw : String) -> String {
  "C_" + moonbit_value_name(raw)
}
