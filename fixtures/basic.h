typedef int score_t;
typedef struct widget widget;

enum mode { MODE_OFF = 0, MODE_ON = 1, MODE_AUTO };

int add(int a, int b);
double mul(double a, double b);
float scale(float value);
score_t score(widget *item, enum mode mode);
void release(widget *item);
int unsupported_buffer(char *buffer);
int unsupported_variadic(const char *format, ...);
int add(int a, int b);
