cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES CXX)

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.cpp"
)

add_executable(app ${DAUKLE_SOURCES})
target_include_directories(app PRIVATE
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../include"
)
target_compile_definitions(app PRIVATE "FEATURE=1" "QUIET")
set_target_properties(app PROPERTIES CXX_STANDARD 17 CXX_STANDARD_REQUIRED ON)

add_custom_target(run COMMAND "$<TARGET_FILE:app>" USES_TERMINAL)
add_dependencies(run app)
