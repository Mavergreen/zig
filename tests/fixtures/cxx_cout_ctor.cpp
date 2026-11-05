#include <iostream>

struct Greeter {
    Greeter() { std::cout << "constructed" << std::endl; }
};

static Greeter greeter;

int main() {
    std::cout << "main" << std::endl;
    return 0;
}
