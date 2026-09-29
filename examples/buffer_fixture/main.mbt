///|
fn main raise {
  let input = b"\x01\x00\x29"
  if abi_buffer_sum(input) != 42 {
    @abort.abort("input buffer with embedded NUL failed")
  }
  let filled = abi_buffer_fill(3)
  if filled.length() != 3 || filled[0] != b'\x01' || filled[2] != b'\x03' {
    @abort.abort("output buffer failed")
  }
  let view = abi_buffer_view(0)
  if view != Some(b"\x00\x2a\x00") ||
    abi_buffer_view(1) != None ||
    abi_buffer_view(2) != Some(Bytes::make(0, b'\x00')) {
    @abort.abort("borrowed return buffer failed")
  }
  let mut invalid_rejected = false
  ignore(abi_buffer_view(3)) catch {
    _ => invalid_rejected = true
  }
  let mut negative_rejected = false
  ignore(abi_buffer_fill(-1)) catch {
    _ => negative_rejected = true
  }
  if !invalid_rejected || !negative_rejected {
    @abort.abort("invalid buffer lengths were accepted")
  }
  let mut short_overflow_rejected = false
  ignore(abi_short(32768)) catch {
    _ => short_overflow_rejected = true
  }
  if abi_short(41) != 42 ||
    abi_ushort(41) != 42 ||
    abi_long(41) != 42 ||
    abi_size(41) != 42 ||
    abi_bool(true) != false ||
    !short_overflow_rejected {
    @abort.abort("scalar ABI bridge failed")
  }
  println("Buffer fixture => 42, zero, NULL, and invalid lengths")
}
