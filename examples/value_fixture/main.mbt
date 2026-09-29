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
  let wide = 2147483648L
  if point_long_bits() == 32 {
    let mut rejected = false
    ignore(point_make(0, wide, 0.0, true)) catch {
      _ => rejected = true
    }
    if !rejected {
      @abort.abort("narrow C long accepted an out-of-range field")
    }
  } else if point_make(0, wide, 0.0, true).y != wide {
    @abort.abort("wide C long was truncated")
  }
  println("Value struct fixture => by-value arguments and return")
}
