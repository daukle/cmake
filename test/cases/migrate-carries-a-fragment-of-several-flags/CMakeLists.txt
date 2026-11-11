cmake_minimum_required(VERSION 3.20)
project(flags LANGUAGES C)
add_executable(app main.c)
target_compile_options(app PRIVATE -DONE=1 -DTWO=2)
