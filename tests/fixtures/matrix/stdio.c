#include <stdio.h>
#include <string.h>

int main(void) {
    char buf[64];
    FILE *f = tmpfile();
    if (f == NULL) return 1;
    if (fprintf(f, "%s %d\n", "stdio", 42) < 0) return 2;
    rewind(f);
    if (fgets(buf, sizeof buf, f) == NULL) return 3;
    fclose(f);
    if (strcmp(buf, "stdio 42\n") != 0) return 4;
    snprintf(buf, sizeof buf, "%.3f", 1.5);
    if (strcmp(buf, "1.500") != 0) return 5;
    printf("stdio ok\n");
    return 0;
}
