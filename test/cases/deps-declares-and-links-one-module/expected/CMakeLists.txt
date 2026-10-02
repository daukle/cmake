add_executable(demo main.c)
# daukle:begin
include(FetchContent)
FetchContent_Declare(basekit-ir URL "https://example.test/ir.tar.gz")
FetchContent_MakeAvailable(basekit-ir)
target_link_libraries(demo PRIVATE basekit-ir)
# daukle:end
