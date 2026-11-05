#include <AvailabilityMacros.h>
#include <stdio.h>

_Static_assert(MAC_OS_X_VERSION_MAX_ALLOWED == 1090, "compiled against an SDK other than Mac OS X 10.9's");

int main(void) {
    printf("%d\n", MAC_OS_X_VERSION_MAX_ALLOWED);
    return 0;
}
