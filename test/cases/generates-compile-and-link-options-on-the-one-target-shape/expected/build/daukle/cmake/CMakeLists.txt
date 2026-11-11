cmake_minimum_required(VERSION 3.20)
project(app VERSION 1.0.0 LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.c"
)

add_executable(app ${DAUKLE_SOURCES})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
target_compile_options(app PRIVATE "-Wall" "-Wextra")
target_link_options(app PRIVATE "-static-libgcc")
