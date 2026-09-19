#include "fixture.h"

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
