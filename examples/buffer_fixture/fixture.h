#ifndef MOONBINDGEN_BUFFER_FIXTURE_H
#define MOONBINDGEN_BUFFER_FIXTURE_H

#define ABI_NULL 1

#include <stddef.h>

int abi_buffer_sum(const void *data, int length);
void abi_buffer_fill(int capacity, void *output);
const void *abi_buffer_view(int mode);
int abi_buffer_view_length(int mode);
int abi_buffer_view_null(int mode);
short abi_short(short value);
unsigned short abi_ushort(unsigned short value);
long abi_long(long value);
size_t abi_size(size_t value);
_Bool abi_bool(_Bool value);

#endif
