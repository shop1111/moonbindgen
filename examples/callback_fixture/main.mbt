///|
type CallbackProbe

///|
extern "C" fn callback_probe_new() -> CallbackProbe = "callback_probe_new"

///|
#borrow(probe)
extern "C" fn callback_probe_touch(probe : CallbackProbe, value : Int) -> Unit = "callback_probe_touch"

///|
extern "C" fn callback_probe_finalizations() -> Int = "callback_probe_finalizations"

///|
fn register_and_drop() -> Unit {
  ignore(register_listener(fn(_) { () }))
}

///|
fn close_captured_probe() -> Unit {
  let probe = callback_probe_new()
  let registration = register_listener(fn(value) {
    callback_probe_touch(probe, value)
  })
  fire_listener(3)
  ignore(registration.close())
}

///|
fn main {
  if call_once(fn(value) { value + 1 }, 41) != 42 {
    @abort.abort("call-scoped callback failed")
  }
  let mut received = 0
  let registration = register_listener(fn(value) { received = received + value })
  fire_listener(20)
  fire_listener(22)
  if received != 42 ||
    registration.is_closed() ||
    !registration.close() ||
    registration.close() ||
    !registration.is_closed() ||
    unregister_count() != 1 {
    @abort.abort("persistent callback lifetime failed")
  }
  fire_listener(100)
  if received != 42 {
    @abort.abort("callback fired after unregister")
  }
  register_and_drop()
  if unregister_count() != 2 {
    @abort.abort("callback finalizer did not unregister")
  }
  close_captured_probe()
  if unregister_count() != 3 || callback_probe_finalizations() != 1 {
    @abort.abort("captured callback object was not released")
  }
  println(
    "Callback fixture => call, unregister once, finalizer, closure release",
  )
}
