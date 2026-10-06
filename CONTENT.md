## What this plugin is

A `daukle.toolchain` named `cmake`: it generates `CMakeLists.txt` into the derived directory,
provisions CMake, and configures, builds and runs a single target. Your repository holds
`daukle.toml` and sources, and the generated file never reaches the project root.

## It sits on top of two other plugins

This is the deepest dependency chain in the organization. It requires `daukle/lifecycle` for the
standard task vocabulary and `daukle/c` for the compiler table, the latter under the alias `cc`
because core refuses a one-letter alias.

That layering is the point of having a C **base** separate from a C **build system**: the two
repositories are not two attempts at CMake, they are a base and the build tool above it. The
duplication only ever read as a collision while the layer between them was unbuilt.

`deps.lua` ships beside the plugin as a second asset and writes the `FetchContent` blocks. It lives
here rather than in `daukle/c` because core refuses one chunk holding `exec` or `provision` to
declare a language at all.

## One target, and the narrowing has already cost something

A project with two targets is not modellable. That is not theoretical: the one real CMake
application in this organization had two, which is why it could not migrate and is archived.

**The compiler a build actually used is reported by nothing.** That is this plugin's stated
narrowing rather than a defect, and it matters most with the optional provisioned compiler, where
you would most want the confirmation.

## The provisioned compiler exists because the obvious route is silent when wrong

`compiler = "21"` provisions clang, Ninja and CMake together, so a build needs nothing installed.

Ninja is not decoration. **Setting only `CMAKE_C_COMPILER` is a silent no-op under the Visual Studio
generator**: a compiler that does not exist configures, builds and runs, reporting success the whole
way. Provisioning a generator alongside the compiler is the mode that actually works, proved on
Windows with no Visual Studio and on Linux with no `make`.

## Where the rest is

The keys, the dependency blocks and the full statement of what this toolchain does not do are in
this repository's `wiki/index.md`, rendered at <https://daukle.github.io/guide/>. `AUTHORING.md` is
the measured detail for anyone changing the plugin.
