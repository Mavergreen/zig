#include <cstdio>
#include <stdexcept>
#include <string>

struct Guard {
    int *n;
    ~Guard() { ++*n; }
};

static void thrower(int *n) {
    Guard g{n};
    throw std::out_of_range("deep");
}

int main() {
    int unwound = 0;
    try {
        thrower(&unwound);
    } catch (const std::logic_error &e) {
        if (std::string(e.what()) != "deep" || unwound != 1) return 1;
        try {
            throw;
        } catch (const std::out_of_range &) {
            std::printf("exceptions ok\n");
            return 0;
        }
    }
    return 2;
}
