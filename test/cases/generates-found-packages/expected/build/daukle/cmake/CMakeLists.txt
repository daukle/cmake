cmake_minimum_required(VERSION 3.20)
project(app VERSION 1.0.0 LANGUAGES C)
message(STATUS "daukle: C compiler ${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION} at ${CMAKE_C_COMPILER}")

find_package(Threads REQUIRED)
find_package(Boost 1.80 REQUIRED COMPONENTS filesystem system)

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/store/*.c"
)

add_library(store ${DAUKLE_SOURCES})
target_link_libraries(store PUBLIC Boost::filesystem)

file(GLOB DAUKLE_SOURCES_2 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/app/*.c"
)

add_executable(app ${DAUKLE_SOURCES_2})
set_target_properties(app PROPERTIES RUNTIME_OUTPUT_DIRECTORY "$<1:${CMAKE_BINARY_DIR}/bin>")
target_link_libraries(app PRIVATE store Threads::Threads)
