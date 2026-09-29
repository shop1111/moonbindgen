///|
fn main raise {
  let first = point_make(3, 4, 1.25, true)
  let second = point_make(5, 6, 2.5, false)
  let combined = point_add(first, second)
  let alias_value = point_passthrough(combined)
  if combined.x != 8 ||
    combined.y != 10 ||
    combined.z != 3.75 ||
    combined.valid ||
    point_score(first) != 9 ||
    alias_value.y != 10 {
    @abort.abort("value struct field conversion failed")
  }
  println("Value struct fixture => by-value arguments and return")
}
