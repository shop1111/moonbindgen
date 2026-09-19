///|
fn main {
  let sum = abi_add(19, 23)
  let mixed : UInt64 = abi_mix(41)
  let scaled = abi_scale(4.0)
  let length = abi_path_length(@utf8.encode("MoonBit"))
  if sum != 42 || mixed != 42 || scaled != 10.0 || length != 7 {
    @abort.abort("generated native ABI fixture failed")
  }
  println("Native ABI fixture => 42, 42, 10, 7")
}
