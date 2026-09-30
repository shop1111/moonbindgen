#include "fixture.h"
#include <moonbit.h>
#include <stdint.h>

typedef struct { int32_t value; } callback_probe;
static int probe_finalizations;

static void callback_probe_finalize(void *raw) {
  (void)raw;
  probe_finalizations++;
}

MOONBIT_FFI_EXPORT callback_probe *callback_probe_new(void) {
  callback_probe *probe = (callback_probe *)moonbit_make_external_object(
      callback_probe_finalize, sizeof(callback_probe));
  probe->value = 0;
  return probe;
}

MOONBIT_FFI_EXPORT void callback_probe_touch(callback_probe *probe, int32_t value) {
  probe->value += value;
}

MOONBIT_FFI_EXPORT int32_t callback_probe_finalizations(void) {
  return probe_finalizations;
}

static void (*listener)(void *, int);
static void *listener_data;
static int unregister_calls;

int call_once(int (*callback)(int), int value) {
  return callback(value);
}

void register_listener(void (*callback)(void *, int), void *user_data) {
  listener = callback;
  listener_data = user_data;
}

void unregister_listener(void *user_data) {
  if (listener_data == user_data && listener != 0) {
    listener = 0;
    listener_data = 0;
    unregister_calls++;
  }
}

void fire_listener(int value) {
  if (listener != 0) listener(listener_data, value);
}

int unregister_count(void) {
  return unregister_calls;
}
