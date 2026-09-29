cmake_minimum_required(VERSION 3.20)
project(app LANGUAGES C)

include(FetchContent)
FetchContent_Declare(basekit-ir URL "https://example.test/ir.tar.gz" URL_HASH SHA256=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef)
FetchContent_MakeAvailable(basekit-ir)

file(GLOB DAUKLE_SOURCES CONFIGURE_DEPENDS
     "${CMAKE_CURRENT_SOURCE_DIR}/../../../src/*.c"
)

add_executable(app ${DAUKLE_SOURCES})
target_link_libraries(app PRIVATE basekit-ir)

add_custom_target(run COMMAND "$<TARGET_FILE:app>" USES_TERMINAL)
add_dependencies(run app)
