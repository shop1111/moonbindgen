#ifndef MOONBINDGEN_NATIVE_FIXTURE_H
#define MOONBINDGEN_NATIVE_FIXTURE_H

typedef int result_t;
typedef struct abi_handle abi_handle;

result_t abi_add(int left, int right);
unsigned long long abi_mix(unsigned long long value);
double abi_scale(double value);
int abi_path_length(const char *path);
int abi_scalar_out(int seed, int *value);
int abi_handle_out(int seed, abi_handle **handle);
int abi_handle_value(abi_handle *handle);
const char *abi_borrowed_text(int mode);
char *abi_owned_text(int mode);
void abi_free_text(char *text);
int abi_free_count(void);

#endif
