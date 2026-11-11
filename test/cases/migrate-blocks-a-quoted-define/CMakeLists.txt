cmake_minimum_required(VERSION 3.20)
project(quoted LANGUAGES C)
add_executable(app main.c)
target_compile_definitions(app PRIVATE [[NAME="x"]])
