cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/greet/*.c"
)

add_library(greet ${DAUKLE_SOURCES})
target_compile_options(greet PRIVATE "-Wall" "SHELL:-include config.h" PUBLIC "-fno-strict-aliasing")
target_link_options(greet INTERFACE "-Wl,--as-needed")

add_library(headers INTERFACE)
target_compile_options(headers INTERFACE "-DHEADERS_OPTION=2")

file(GLOB DAUKLE_SOURCES_3 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/app/*.c"
)

add_executable(app ${DAUKLE_SOURCES_3})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
target_link_libraries(app PRIVATE greet headers)
target_compile_options(app PRIVATE "-O2")
target_link_options(app PRIVATE "-static-libgcc")
