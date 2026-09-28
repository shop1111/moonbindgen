///|
fn main raise {
  let sum = abi_add(19, 23)
  let mixed : UInt64 = abi_mix(41)
  let scaled = abi_scale(4.0)
  let length = abi_path_length(@utf8.encode("MoonBit"))
  let (scalar_status, scalar) = abi_scalar_out(41)
  let (scalar_error, scalar_default) = abi_scalar_out(-1)
  let (handle_status, handle) = abi_handle_out(42)
  let (handle_error, _) = abi_handle_out(-1)
  let borrowed = abi_borrowed_text(0)
  let borrowed_null = abi_borrowed_text(1)
  let owned = abi_owned_text(0)
  let owned_null = abi_owned_text(1)
  let mut malformed_rejected = false
  ignore(abi_owned_text(2)) catch {
    _ => malformed_rejected = true
  }
  if sum != 42 ||
    mixed != 42 ||
    scaled != 10.0 ||
    length != 7 ||
    scalar_status != 0 ||
    scalar != 42 ||
    scalar_error != 7 ||
    scalar_default != 0 ||
    handle_status != 0 ||
    abi_handle_value(handle) != 42 ||
    handle_error != 9 ||
    borrowed != Some("MoonBit") ||
    borrowed_null != None ||
    owned != Some("owned") ||
    owned_null != None ||
    !malformed_rejected ||
    abi_free_count() != 2 {
    @abort.abort("generated native ABI fixture failed")
  }
  println("Native ABI fixture => 42, outputs and strings")
}
