# daukle/cmake

The CMake toolchain. It generates `CMakeLists.txt` into the derived directory, provisions CMake,
and configures, builds and runs a single target. Your repository holds `daukle.toml` and sources.

## Declaring it

```toml
[plugins]
cmake = "daukle/cmake@^1"

[toolchains.cmake]
name = "greeter"
kind = "executable"
sources = ["src/main.c"]
```

## Keys

| key | meaning |
| --- | --- |
| `name` | the target name |
| `kind` | `executable` or `library` |
| `sources` | the translation units |
| `version` | which CMake to provision |
| `compiler` | provision clang and Ninja too, so nothing need be installed |
| `buildType` | `Debug` or `Release` |
| `configureArgs`, `buildArgs` | passed straight through |

## The optional provisioned compiler

`compiler = "21"` provisions clang, Ninja and CMake, so a build needs nothing installed at all.

**Setting only `CMAKE_C_COMPILER` is a silent no-op under the Visual Studio generator**: a compiler
that does not exist configures, builds and runs. The mode that works is a provisioned Ninja
alongside the compiler, which is what this plugin does, proved on Windows with no Visual Studio and
on Linux with no `make`.

## Dependencies

`deps.lua` ships beside the plugin as a second asset and writes `FetchContent` blocks. It moved
here from `daukle/c`, because core refuses one chunk that holds `exec` or `provision` to declare a
language at all.

## What it does not do

**One target.** A project with two is not modellable, which is why the one real CMake application
in this organization could not migrate. The compiler a build actually used is reported by nothing,
which is this plugin's stated narrowing rather than a defect.
