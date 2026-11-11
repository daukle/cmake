cmake_minimum_required(VERSION 3.20)
project(app VERSION 1.0.0 LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.c"
)

add_library(app ${DAUKLE_SOURCES})
set_target_properties(app PROPERTIES C_STANDARD "11" C_STANDARD_REQUIRED ON)
