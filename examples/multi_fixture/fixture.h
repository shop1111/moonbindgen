#ifndef MOONBINDGEN_MULTI_FIXTURE_H
#define MOONBINDGEN_MULTI_FIXTURE_H

typedef struct token token;

int make_pair(int base, int *left, long *right, token **handle);
int token_value(token *handle);
token *token_new(int value);
void token_retain(token *handle);
token *token_borrow(token *handle);
void token_free(token *handle);
int token_free_count(void);
int token_release_count(void);

#endif
