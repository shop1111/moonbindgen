#ifndef MOONBINDGEN_NATIVE_FIXTURE_H
#define MOONBINDGEN_NATIVE_FIXTURE_H

typedef int result_t;

result_t abi_add(int left, int right);
unsigned long long abi_mix(unsigned long long value);
double abi_scale(double value);
int abi_path_length(const char *path);

#endif
