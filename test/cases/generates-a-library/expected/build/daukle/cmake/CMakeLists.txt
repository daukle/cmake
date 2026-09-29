cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES C)

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.c"
)

add_library(app ${DAUKLE_SOURCES})
set_target_properties(app PROPERTIES C_STANDARD "11" C_STANDARD_REQUIRED ON)
