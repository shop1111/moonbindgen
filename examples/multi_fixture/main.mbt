///|
fn create_and_drop_resource() -> Unit raise {
  guard token_new(9) is Some(managed) else {
    @abort.abort("resource creation failed")
  }
  ignore(token_value(managed.unsafe_raw()))
}

///|
fn make_borrowed_view() -> MbgView_token_borrow raise {
  guard token_new(11) is Some(managed) else {
    @abort.abort("resource creation failed")
  }
  guard token_borrow(managed) is Some(view) else {
    @abort.abort("resource view creation failed")
  }
  view
}

///|
fn use_borrowed_view() -> Unit raise {
  let view = make_borrowed_view()
  if view.with_raw(fn(raw) { token_value(raw) }) != 11 {
    @abort.abort("borrowed view did not retain its owner")
  }
}

///|
fn main raise {
  let value = make_pair(20)
  if value.status != 0 ||
    value.left != 21 ||
    value.right != 22 ||
    token_value(value.handle) != 42 {
    @abort.abort("named scalar and handle outputs failed")
  }
  token_free(value.handle)
  let failed = make_pair(-1)
  if failed.status != -1 ||
    failed.left != 0 ||
    failed.right != 0 ||
    token_free_count() != 1 {
    @abort.abort("failure output or handle cleanup failed")
  }
  let before_free = token_free_count()
  let before_release = token_release_count()
  guard token_new(7) is Some(managed) else {
    @abort.abort("resource creation failed")
  }
  guard token_borrow(managed) is Some(view) else {
    @abort.abort("borrowed resource view failed")
  }
  let retained = managed.retain()
  if token_value(view.unsafe_raw()) != 7 ||
    !managed.close() ||
    managed.close() ||
    !managed.is_closed() {
    @abort.abort("resource close did not run exactly once")
  }
  let mut view_rejected = false
  ignore(view.unsafe_raw()) catch {
    _ => view_rejected = true
  }
  if !view_rejected ||
    retained.is_closed() ||
    token_value(retained.unsafe_raw()) != 7 ||
    !retained.close() ||
    retained.close() ||
    token_free_count() != before_free + 1 ||
    token_release_count() != before_release + 2 {
    @abort.abort("retained resource or borrowed view lifetime failed")
  }
  let before_finalizer = token_free_count()
  create_and_drop_resource()
  if token_free_count() != before_finalizer + 1 {
    @abort.abort("resource finalizer did not release the handle")
  }
  let before_view = token_free_count()
  use_borrowed_view()
  if token_free_count() != before_view + 1 {
    @abort.abort("borrowed view owner was not finalized")
  }
  println(
    "Multi-output and resource fixture => named fields, close once, retain",
  )
}
