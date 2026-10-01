cmake_minimum_required(VERSION 3.20)
project(basekitir LANGUAGES C)

add_library(basekit-ir STATIC ir.c)
target_include_directories(basekit-ir PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
