#include "fixture.h"
#include <stdlib.h>

struct token { int value; int references; };
static int free_count = 0;
static int release_count = 0;

int make_pair(int base, int *left, long *right, token **handle) {
  if (base < 0) return -1;
  *left = base + 1;
  *right = (long)base + 2;
  *handle = (token *)malloc(sizeof(token));
  if (*handle == NULL) return -2;
  (*handle)->value = *left + (int)*right - 1;
  (*handle)->references = 1;
  return 0;
}

int token_value(token *handle) { return handle->value; }
token *token_new(int value) {
  token *handle = (token *)malloc(sizeof(token));
  if (handle == NULL) return NULL;
  handle->value = value;
  handle->references = 1;
  return handle;
}
void token_retain(token *handle) { handle->references++; }
token *token_borrow(token *handle) { return handle; }
void token_free(token *handle) {
  release_count++;
  handle->references--;
  if (handle->references == 0) { free_count++; free(handle); }
}
int token_free_count(void) { return free_count; }
int token_release_count(void) { return release_count; }
