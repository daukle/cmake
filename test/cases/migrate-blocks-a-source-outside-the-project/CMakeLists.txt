cmake_minimum_required(VERSION 3.20)
project(configured LANGUAGES C)
configure_file(main.c ${CMAKE_CURRENT_BINARY_DIR}/configured.c COPYONLY)
add_executable(app ${CMAKE_CURRENT_BINARY_DIR}/configured.c)
