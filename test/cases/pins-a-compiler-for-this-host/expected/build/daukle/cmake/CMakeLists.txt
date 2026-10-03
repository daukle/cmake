cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES C)

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.c"
)

add_executable(app ${DAUKLE_SOURCES})

add_custom_target(run COMMAND "$<TARGET_FILE:app>" USES_TERMINAL VERBATIM)
add_dependencies(run app)
