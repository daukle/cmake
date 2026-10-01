# Authoring notes

This plugin is multi-file. `plugin.lua` declares the toolchain and the three tasks; `lib/manifest`
validates the `[toolchains.cmake]` block into a spec; `lib/generate` renders that spec into
`CMakeLists.txt`; `lib/cmakes` holds the pinned archive table. Only `lib/manifest` reads
`context.config` or `context.toolchain`.

## What this plugin owns

One generated `CMakeLists.txt` under `build/daukle/cmake/`, and nothing in your tree. A repository
using this toolchain holds `daukle.toml` and `src/` and no build file of its own. Do not edit the
generated file: every `sync` overwrites it.

The modelled surface is **one target**. `configureArgs`, `buildArgs` and `runArgs` are the escape
hatch for everything the keys below do not reach, and they are passed through verbatim.

## The toolchain block

```toml
[toolchains.cmake]
version = "4.4"
```

| key | default | what it does |
| --- | --- | --- |
| `version` | required | which pinned CMake to provision |
| `language` | `"c"` | `"c"` or `"c++"` |
| `kind` | `"executable"` | `"executable"` or `"library"` |
| `sources` | per language | globs, relative to the project, resolved with `CONFIGURE_DEPENDS`. `c` defaults to `["src/*.c"]`, `c++` to `["src/*.cpp", "src/*.cc", "src/*.cxx"]` |
| `includes` | none | directories added as `PRIVATE` include paths |
| `defines` | none | compile definitions |
| `standard` | none | the language standard, e.g. `17` |
| `buildType` | `"Debug"` | the CMake build type |
| `generator` | none | passed to `-G`; see the generator note below |
| `configureArgs`, `buildArgs`, `runArgs` | none | passed through verbatim |

`version` is a pinned `major.minor`, and **a range is refused**. `">=4.0"` and `"^4.4"` are both
errors: this plugin ships a table of exact releases with their published digests, and matching a
range would mean resolving a version it has no digest for.

Paths in `sources` and `includes` may not climb out of the project. An absolute path, a path
holding `..`, and a backslash are all refused.

**A key this toolchain does not know is refused, not ignored.** `buildtype` instead of `buildType`
would otherwise build the wrong thing in silence.

**Anything interpolated into the generated file is refused if it carries a CMake metacharacter**
(`"`, `\`, `$`, `)`, `;`, or a newline). That covers `sources`, `includes`, `defines` and
`standard`, plus a dependency's `url` and `sha256`. It deliberately does **not** cover
`configureArgs`, `buildArgs` or `runArgs`: those reach the process as argv and never enter the
generated file, which is exactly why they are the escape hatch for anything the rule refuses.

## What you must have installed

**CMake is provisioned. A compiler and a build tool are not.**

- On Linux and macOS, **`make` must be installed**, along with a C or C++ compiler.
- On Windows, a Visual Studio installation is enough; CMake's default generator finds MSVC unaided.

**Do not set `generator = "Ninja"` on Windows** expecting it to work outside a developer prompt.
Ninja needs the environment `vcvarsall.bat` produces, a plugin cannot produce it, and CMake's
default generator does not need it. This is why the plugin names no generator unless you name one.

A positive case cannot name a real generator, because which ones exist differs per platform.
`names-a-generator-cmake-cannot-create` covers the `-G` emission instead: only CMake's own
generator lookup says "Could not create named generator", so the refusal proves the value reached
the command line.

## The compiler is CMake's choice, and daukle reports nothing about it

daukle's tool report lists what `daukle.provision` or `daukle.tool` resolved. The compiler is
neither: CMake finds it, and a plugin cannot print. So a CMake build's report names the CMake it
provisioned and says nothing about the compiler that did the work. That is a deliberate narrowing,
not a defect, and it is the reason `cc` rather than this plugin is where reporting gets solved.

## Two things you will meet

**`cmake:run` runs your program from the CMake binary directory**, `build/daukle/cmake/_b`, not
from your project root and not from the derived directory. A program writing `ran.txt` writes it
there. Measured, not assumed.

**Bumping the pinned CMake does not require `daukle clean`.** Measured on 2026-09-29 by building
with 4.4.3, repinning to 4.4.2 and rebuilding into the same `_b/`: CMake noticed the new
`CMAKE_COMMAND`, reconfigured silently, and the cache moved to the new version with no warning and
no error. That was a patch bump on the Visual Studio generator on Windows; a major bump or a
generator change was not measured, so if a rebuild after a bump behaves oddly, `daukle clean` is
still the first thing to try.

## Dependencies

A resolved module's `cmake` block becomes one `FetchContent_Declare` plus one
`FetchContent_MakeAvailable`, and all of them become a single `target_link_libraries`.

```toml
  [modules.ir.cmake]
  package = "basekit-ir"
  url = "https://example.test/ir.tar.gz"
  sha256 = "..."
```

**`sha256` is required here, and optional in `daukle/c`.** The difference is deliberate:
`daukle/c` edits a region of a file you wrote and read, so an unverified download is at least
visible in your own tree. This plugin writes a file you are told not to read, so an unverified
download would be invisible. It must be exactly 64 hex digits, `package` must be usable as a
CMake target name, and `url` may carry no CMake metacharacter: all three land in the same
generated statement, so validating only one of them would close one field of three.

`target_link_libraries` uses the `package` name as the target name, which assumes the fetched
project exports a target called that. `links-a-dependency-it-fetches` verifies it end to end: the
archive is built and digested by the case's own `setup.sh`, so the fetch, the digest check, the
subbuild, the link and the include propagation are all real, and `cmake:run` executes the result
rather than asserting a file. `links-a-resolved-dependency` keeps its unfetchable fixture url and
remains the byte-exact generation case.

## Tasks

`cmake:configure`, `cmake:build` (depends on configure) and `cmake:run` (depends on build).
`cmake:run` on a `kind = "library"` project is an error, not a no-op.

**No task declares `partOf`.** No plugin in this org declares `build`, and a `partOf` naming an
undeclared task is an error naming both, which would make this plugin unusable standalone. Wire it
up yourself:

```toml
[tasks.build]
dependsOn = ["cmake:build"]
```

Both the configure-time `-DCMAKE_BUILD_TYPE` and `--config` at build are always passed, and
exactly one takes effect: a single-config generator honours the first and ignores the second, a
multi-config generator does the reverse.

## Tests

`test/run.sh` runs every directory under `test/cases/` against a real daukle, because this
plugin's output is a generated file daukle writes and a real CMake consumes, and a stub of either
would be testing the stub.

- a case with `expected/` must sync cleanly and match every file in it, byte for byte
- a case with `expect-error.txt` must fail with a message carrying that clause
- a case with `task.txt` runs that task, and asserts `produces.txt` or `expect-task-error.txt`
- every success case is synced **twice** and must match after both
- a case whose `expected/` is empty is a failure, not a pass
- a case with `setup.sh` runs it in the sandbox first, so a manifest can carry a digest of
  something the case builds at test time rather than one committed beside it

A fixture a case digests must be written **outside** the sandbox, because daukle refuses a
generated file that carries the project root and the url lands in `CMakeLists.txt` verbatim. The
root is matched as a substring, so a name merely suffixed with the sandbox's still carries it.

```sh
DAUKLE=/path/to/daukle sh test/run.sh
```

The task cases provision a real CMake and need a compiler on the host, so they run by default only
on Linux. Elsewhere they are opt-in:

```sh
DAUKLE=/path/to/daukle DAUKLE_CMAKE_E2E=1 sh test/run.sh
```

**Read the skip count, not only the failure count.** A skip that is invisible in a summary is a
green run that tested nothing.

`.gitattributes` pins `* -text`, and it is load bearing rather than tidy. daukle writes LF on every
platform, so a checkout under `core.autocrlf=true` rewrites the fixtures and the byte-exact cases
fail on Windows for a reason that has nothing to do with the plugin.

## Limits

The compiler a build uses is reported by nothing. That is this plugin's stated narrowing rather
than a gap: CMake picks it, and nothing here asks which.
