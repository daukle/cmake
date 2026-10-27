cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES CXX)
message(STATUS "daukle: CXX compiler ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION} at ${CMAKE_CXX_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.cpp"
)

add_executable(app ${DAUKLE_SOURCES})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
target_include_directories(app PRIVATE
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../include"
)
target_compile_definitions(app PRIVATE "FEATURE=1" "QUIET")
set_target_properties(app PROPERTIES CXX_STANDARD "17" CXX_STANDARD_REQUIRED ON)
