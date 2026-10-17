cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES C)

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/lib/*.c"
)

add_library(greet ${DAUKLE_SOURCES})
target_link_libraries(greet PRIVATE m)

file(GLOB DAUKLE_SOURCES_2 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/app/*.c"
)

add_executable(app ${DAUKLE_SOURCES_2})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
target_link_libraries(app PRIVATE greet D3D11.lib -pthread /usr/lib/libz.a)
