cmake_minimum_required(VERSION 3.20)
project(app VERSION 1.0.0 LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/fixed/*.c"
)

add_library(fixed STATIC ${DAUKLE_SOURCES})

file(GLOB DAUKLE_SOURCES_2 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/loaded/*.c"
)

add_library(loaded SHARED ${DAUKLE_SOURCES_2})
set_target_properties(loaded PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")

file(GLOB DAUKLE_SOURCES_3 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/plugin/*.c"
)

add_library(plugin MODULE ${DAUKLE_SOURCES_3})
set_target_properties(plugin PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")

file(GLOB DAUKLE_SOURCES_4 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/parts/*.c"
)

add_library(parts OBJECT ${DAUKLE_SOURCES_4})
