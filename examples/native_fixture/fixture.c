#include "fixture.h"
#include <stdlib.h>
#include <string.h>

struct abi_handle { int value; };
static struct abi_handle sample_handle = {42};
static int free_count = 0;

result_t abi_add(int left, int right) { return left + right; }

unsigned long long abi_mix(unsigned long long value) {
  return value + 1ULL;
}

double abi_scale(double value) { return value * 2.5; }

int abi_path_length(const char *path) {
  int length = 0;
  while (path[length] != '\0') {
    length += 1;
  }
  return length;
}

int abi_scalar_out(int seed, int *value) {
  if (seed < 0) return 7;
  *value = seed + 1;
  return 0;
}

int abi_handle_out(int seed, abi_handle **handle) {
  if (seed < 0) return 9;
  *handle = &sample_handle;
  return 0;
}

int abi_handle_value(abi_handle *handle) { return handle->value; }

const char *abi_borrowed_text(int mode) {
  return mode == 1 ? NULL : "MoonBit";
}

char *abi_owned_text(int mode) {
  if (mode == 1) return NULL;
  const char *source = mode == 2 ? "\xff" : "owned";
  size_t size = strlen(source) + 1;
  char *text = (char *)malloc(size);
  if (text != NULL) memcpy(text, source, size);
  return text;
}

void abi_free_text(char *text) {
  free_count += 1;
  free(text);
}

int abi_free_count(void) { return free_count; }
