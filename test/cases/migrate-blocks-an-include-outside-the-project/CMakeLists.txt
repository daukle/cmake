cmake_minimum_required(VERSION 3.20)
project(outside LANGUAGES C)
add_executable(app main.c)
target_include_directories(app PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../elsewhere)
