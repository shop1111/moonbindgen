#include "fixture.h"
#include <stdint.h>
#include <stddef.h>

int abi_buffer_sum(const void *data, int length) {
  const uint8_t *bytes = (const uint8_t *)data;
  int sum = 0;
  for (int i = 0; i < length; i++) sum += bytes[i];
  return sum;
}

void abi_buffer_fill(int capacity, void *output) {
  uint8_t *bytes = (uint8_t *)output;
  for (int i = 0; i < capacity; i++) bytes[i] = (uint8_t)(i + 1);
}

const void *abi_buffer_view(int mode) {
  static const uint8_t value[] = {0, 42, 0};
  if (mode == 0) return value;
  return NULL;
}

int abi_buffer_view_length(int mode) {
  if (mode == 0) return 3;
  if (mode == 3) return 1;
  return 0;
}

int abi_buffer_view_null(int mode) { return mode == 1 ? ABI_NULL : 0; }

short abi_short(short value) { return (short)(value + 1); }
unsigned short abi_ushort(unsigned short value) { return (unsigned short)(value + 1); }
long abi_long(long value) { return value + 1; }
size_t abi_size(size_t value) { return value + 1; }
_Bool abi_bool(_Bool value) { return !value; }
