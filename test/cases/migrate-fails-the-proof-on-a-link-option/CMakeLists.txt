cmake_minimum_required(VERSION 3.20)
project(linked LANGUAGES C)
add_executable(app main.c)
target_link_options(app PRIVATE $<IF:$<C_COMPILER_ID:MSVC>,/STACK:4000000,-rdynamic>)
