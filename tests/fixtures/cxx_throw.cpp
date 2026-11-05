#include <cstdio>
#include <stdexcept>

int main() {
    try {
        throw std::runtime_error("thrown");
    } catch (const std::exception &e) {
        std::printf("caught %s\n", e.what());
    }
    return 0;
}
