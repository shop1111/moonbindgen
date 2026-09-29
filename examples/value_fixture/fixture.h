#ifndef MOONBINDGEN_VALUE_FIXTURE_H
#define MOONBINDGEN_VALUE_FIXTURE_H

typedef struct point {
  int x;
  long y;
  double z;
  _Bool valid;
} point;

point point_make(int x, long y, double z, _Bool valid);
point point_add(point left, point right);
int point_score(point value);
int point_long_bits(void);
typedef point point_alias;
point_alias point_passthrough(point_alias value);

typedef struct packed_bits {
  unsigned int flags : 3;
  int value;
} packed_bits;

packed_bits packed_bits_identity(packed_bits value);

typedef struct flex_bytes {
  int count;
  unsigned char data[];
} flex_bytes;

flex_bytes flex_bytes_identity(flex_bytes value);

#endif
