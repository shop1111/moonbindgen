///|
/// A C declarator shape retained before deciding whether its ABI is supported.
priv struct CTypeModel {
  base : String
  pointer_depth : Int
  pointee_const : Bool
  pointer_const : Bool
  array : Bool
  function_pointer : Bool
  record : Bool
  enumeration : Bool
}

///|
fn c_type_model(raw : String) -> CTypeModel {
  let spelling = raw.trim().to_owned()
  let function_pointer = spelling.contains("(*") || spelling.contains("( *")
  let array = spelling.contains("[") && spelling.has_suffix("]")
  let mut source = spelling.replace_all(old="  ", new=" ")
  let mut pointer_const = false
  if source.has_suffix(" const") {
    pointer_const = true
    source = source[:source.length() - 6].trim().to_owned()
  }
  let mut pointer_depth = 0
  if !function_pointer && !array {
    while source.has_suffix("*") {
      pointer_depth += 1
      source = source[:source.length() - 1].trim().to_owned()
    }
  }
  let mut pointee_const = false
  if source.has_prefix("const ") {
    pointee_const = true
    source = source[6:].trim().to_owned()
  }
  if source.has_prefix("volatile ") {
    source = source[9:].trim().to_owned()
  }
  let record = source.has_prefix("struct ") || source.has_prefix("union ")
  let enumeration = source.has_prefix("enum ")
  {
    base: source,
    pointer_depth,
    pointee_const,
    pointer_const,
    array,
    function_pointer,
    record,
    enumeration,
  }
}

///|
fn is_v2_byte_pointer(raw : String, const_required~ : Bool) -> Bool {
  let shape = c_type_model(raw)
  shape.pointer_depth == 1 &&
  !shape.array &&
  !shape.function_pointer &&
  !shape.pointer_const &&
  !shape.record &&
  !shape.enumeration &&
  (
    shape.base == "void" ||
    shape.base == "char" ||
    shape.base == "signed char" ||
    shape.base == "unsigned char"
  ) &&
  shape.pointee_const == const_required
}

///|
fn is_v2_callback_pointer(raw : String) -> Bool {
  c_type_model(raw).function_pointer
}
