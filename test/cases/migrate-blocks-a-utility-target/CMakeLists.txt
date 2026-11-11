cmake_minimum_required(VERSION 3.20)
project(util LANGUAGES C)
add_executable(app main.c)
add_custom_target(docs COMMAND ${CMAKE_COMMAND} -E echo docs)
