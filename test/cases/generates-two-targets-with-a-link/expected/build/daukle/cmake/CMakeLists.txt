cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES C)

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/lib/*.c"
)

add_library(greet ${DAUKLE_SOURCES})

file(GLOB DAUKLE_SOURCES_2 CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/app/*.c"
)

add_executable(app ${DAUKLE_SOURCES_2})
target_link_libraries(app PRIVATE greet)

add_custom_target(run-app COMMAND "$<TARGET_FILE:app>" USES_TERMINAL VERBATIM)
add_dependencies(run-app app)

add_custom_target(run COMMAND "$<TARGET_FILE:app>" USES_TERMINAL VERBATIM)
add_dependencies(run app)
