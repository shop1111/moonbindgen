#include "fixture.h"

point point_make(int x, long y, double z, _Bool valid) {
  point result = { x, y, z, valid };
  return result;
}

point point_add(point left, point right) {
  point result = {
    left.x + right.x,
    left.y + right.y,
    left.z + right.z,
    left.valid && right.valid
  };
  return result;
}

int point_score(point value) {
  return value.x + (int)value.y + (int)value.z + (value.valid ? 1 : 0);
}

int point_long_bits(void) { return (int)(sizeof(long) * 8); }

point_alias point_passthrough(point_alias value) { return value; }

packed_bits packed_bits_identity(packed_bits value) { return value; }

flex_bytes flex_bytes_identity(flex_bytes value) { return value; }
