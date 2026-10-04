# cmake

The cmake toolchain plugin for daukle. It compiles, links and runs a C or C++ project from a repository holding only daukle.toml and src/, with a CMake it provisions and verifies itself, generating one CMakeLists.txt into build/daukle/cmake/ and nothing in the user's tree.

## Examples

- [`cmake-c-executable`](examples/cmake-c-executable): A managed C project.
- [`cmake-cpp-executable`](examples/cmake-cpp-executable): The same managed toolchain as `cmake-c-executable`, in C++, and with two keys that example does not use.

## License

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
