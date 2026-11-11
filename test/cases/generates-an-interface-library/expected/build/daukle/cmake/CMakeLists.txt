cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/fixed/*.c"
)

add_library(fixed STATIC ${DAUKLE_SOURCES})

add_library(headers INTERFACE)
target_link_libraries(headers INTERFACE fixed)
target_include_directories(headers INTERFACE
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../include"
)
target_compile_definitions(headers INTERFACE "HEADERS_INLINE=1")

file(GLOB DAUKLE_SOURCES_3 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/app/*.c"
)

add_executable(app ${DAUKLE_SOURCES_3})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
target_link_libraries(app PRIVATE headers)
