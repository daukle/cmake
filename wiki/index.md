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

The dependency writer is a MODULE of this plugin and writes `FetchContent` blocks. Name it on the
same line, with its own grant and without the toolchain, from `daukle 0.9.0`:

```toml
[plugins]
cmake = { resolver = "github", coordinate = "daukle/cmake@^1.5.0", modules = ["deps"] }
```

## Which compiler a build used

Every configure prints it, `daukle: C compiler Clang 21.1.8 at <path>` for the provisioned
compiler and the host's alike. CMake's own "The C compiler identification is" line appears only on
the configure that first detects the compiler, so without this a later run's log, `cmake:build`'s
included, would not say.

## What it does not do

Several executables and libraries in one project are modelled through
`targets`; see `AUTHORING.md`.
