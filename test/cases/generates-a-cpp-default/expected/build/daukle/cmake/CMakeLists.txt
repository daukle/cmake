cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES CXX)

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.cpp"
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.cc"
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.cxx"
)

add_executable(app ${DAUKLE_SOURCES})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
