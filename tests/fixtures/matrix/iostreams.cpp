#include <iostream>
#include <sstream>
#include <string>

int main() {
    std::ostringstream out;
    out << "iostreams " << 42 << ' ' << 1.5;
    std::istringstream in(out.str());
    std::string word;
    int n = 0;
    double d = 0;
    in >> word >> n >> d;
    if (word != "iostreams" || n != 42 || d != 1.5) return 1;
    std::cout << "iostreams ok" << std::endl;
    return 0;
}
