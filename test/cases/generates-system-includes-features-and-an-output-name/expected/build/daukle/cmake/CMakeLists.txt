cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/greet/*.c"
)

add_library(greet ${DAUKLE_SOURCES})
target_include_directories(greet SYSTEM PRIVATE
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../vendor/private"
    PUBLIC
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../vendor/public"
)
target_compile_features(greet PUBLIC "c_std_11")
set_target_properties(greet PROPERTIES C_EXTENSIONS OFF)

add_library(headers INTERFACE)
target_include_directories(headers SYSTEM INTERFACE
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../vendor/headers"
)
target_compile_features(headers INTERFACE "c_std_99")

file(GLOB DAUKLE_SOURCES_3 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/app/*.c"
)

add_executable(app ${DAUKLE_SOURCES_3})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
target_link_libraries(app PRIVATE greet headers)
target_include_directories(app PRIVATE
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../include"
)
target_compile_features(app PRIVATE "c_std_11")
set_target_properties(app PROPERTIES C_EXTENSIONS ON)
set_target_properties(app PROPERTIES OUTPUT_NAME "greeter-tool")
