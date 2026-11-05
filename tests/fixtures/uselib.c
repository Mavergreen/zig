#include <stdio.h>

int zig_add(int a, int b);
int zig_now_nonzero(void);

int main(void) {
    printf("%d %d\n", zig_add(2, 3), zig_now_nonzero());
    return 0;
}
