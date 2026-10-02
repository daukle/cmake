#include <iostream>

int main() {
#if EXAMPLE_GREETING
    std::cout << "hello from daukle" << '\n';
#else
    std::cout << "the define never arrived" << '\n';
#endif
    return 0;
}
