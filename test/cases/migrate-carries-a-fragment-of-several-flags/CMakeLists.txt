cmake_minimum_required(VERSION 3.20)
project(flags LANGUAGES C)
add_executable(app main.c)
set_target_properties(app PROPERTIES COMPILE_FLAGS "-DONE=1 -DTWO=2")
