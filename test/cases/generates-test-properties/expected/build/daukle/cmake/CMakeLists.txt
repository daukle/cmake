cmake_minimum_required(VERSION 3.20)
project(app VERSION 1.0.0 LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.c"
)

add_executable(app ${DAUKLE_SOURCES})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")

enable_testing()
add_test(NAME unit COMMAND app WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../../test/data")
set_tests_properties(unit PROPERTIES LABELS "fast;unit" TIMEOUT 30)
add_test(NAME rejects-bad-input COMMAND app "bad")
set_tests_properties(rejects-bad-input PROPERTIES WILL_FAIL ON)
