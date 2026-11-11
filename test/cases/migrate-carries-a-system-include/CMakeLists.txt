cmake_minimum_required(VERSION 3.20)
project(system LANGUAGES C)
add_executable(app main.c)
target_include_directories(app SYSTEM PRIVATE third)
