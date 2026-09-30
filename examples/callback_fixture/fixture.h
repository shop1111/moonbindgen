#ifndef MOONBINDGEN_CALLBACK_FIXTURE_H
#define MOONBINDGEN_CALLBACK_FIXTURE_H

int call_once(int (*callback)(int), int value);
void register_listener(void (*callback)(void *, int), void *user_data);
void unregister_listener(void *user_data);
void fire_listener(int value);
int unregister_count(void);

#endif
