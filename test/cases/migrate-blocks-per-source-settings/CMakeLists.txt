cmake_minimum_required(VERSION 3.20)
project(persource LANGUAGES C)
add_executable(app main.c other.c)
set_source_files_properties(other.c PROPERTIES COMPILE_DEFINITIONS OTHER=1)
