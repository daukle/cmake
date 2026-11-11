cmake_minimum_required(VERSION 3.20)
project(app VERSION 1.0.0 LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/base/*.c"
)

add_library(base ${DAUKLE_SOURCES})
target_include_directories(base INTERFACE
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../include/base"
)

file(GLOB DAUKLE_SOURCES_2 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/lib/*.c"
)

add_library(greet ${DAUKLE_SOURCES_2})
target_link_libraries(greet PUBLIC base)
target_include_directories(greet PRIVATE
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/lib"
    PUBLIC
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../include"
)
target_compile_definitions(greet PUBLIC "GREET_BASE=7" INTERFACE "GREET_CONSUMER=1")

file(GLOB DAUKLE_SOURCES_3 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/app/*.c"
)

add_executable(app ${DAUKLE_SOURCES_3})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
target_link_libraries(app PRIVATE greet)
