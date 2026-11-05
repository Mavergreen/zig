#include <CoreFoundation/CoreFoundation.h>

int main(void) {
    CFStringRef s = CFStringCreateWithCString(kCFAllocatorDefault, "hello", kCFStringEncodingUTF8);
    CFShow(s);
    CFRelease(s);
    return 0;
}
