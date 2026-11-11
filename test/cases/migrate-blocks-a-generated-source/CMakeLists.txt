cmake_minimum_required(VERSION 3.20)
project(gen LANGUAGES C)
add_custom_command(OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/gen.c
                   COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/main.c ${CMAKE_CURRENT_BINARY_DIR}/gen.c)
add_executable(app ${CMAKE_CURRENT_BINARY_DIR}/gen.c)
