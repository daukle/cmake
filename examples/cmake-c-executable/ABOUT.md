# cmake-c-executable

A managed C project. The repository holds `daukle.toml` and `src/` and **no `CMakeLists.txt`**.
daukle downloads CMake, verifies it against a digest the plugin pins, generates one
`CMakeLists.txt` into `build/daukle/cmake/`, and runs CMake over it.

```console
$ daukle cmake:run
hello from daukle
```

`daukle sync` on its own generates `build/daukle/cmake/CMakeLists.txt` and nothing in your tree.

## This example is exactly what your project would hold

It names a pinned resolver and a published coordinate, so the directory can be copied anywhere and
`daukle sync` works:

```toml
[resolvers.github]
url = "https://raw.githubusercontent.com/daukle/daukle/<commit>/plugins/github-releases.lua"
sha256 = "..."

[plugins]
cmake = { resolver = "github", coordinate = "daukle/cmake@^1.0.0" }
```

Nothing vendors a copy of the plugin. **The suite then runs it twice**: once as committed, against
the published release, and once with this repository's working tree staged over a copy, so a break
in the plugin as it stands now reddens this repository rather than waiting for a release.

## What to look at

**The generated file is daukle's, not yours.** Every `sync` overwrites it, and `build/daukle/`
carries a ledger of what daukle wrote so `daukle clean` removes exactly that and nothing else. Read
it to see what the toolchain block became; do not edit it.

**`sources` defaults to `src/*.c`** and is resolved with `CONFIGURE_DEPENDS`, so adding a file needs
no edit anywhere. A glob is used rather than a list because a list is the thing people forget to
update.

**`standard = 17` becomes `C_STANDARD`.** Anything interpolated into the generated file is refused
if it carries a CMake metacharacter, which is why `configureArgs`, `buildArgs` and `runArgs` exist:
they reach the process as argv and never enter the generated text, so they are the escape hatch for
whatever that rule refuses.

**A key the toolchain does not know is refused, not ignored.** `buildtype` for `buildType` would
otherwise build the wrong thing in silence.

## What you still need installed

**CMake is provisioned. A compiler and a build tool are not.** On Linux and macOS you need `make`
and a C compiler; on Windows a Visual Studio installation is enough, because CMake's default
generator finds MSVC unaided. Do not set `generator = "Ninja"` on Windows expecting it to work
outside a developer prompt: Ninja needs the environment `vcvarsall.bat` produces, and a plugin
cannot produce it.

**daukle reports nothing about the compiler.** It reports what it provisioned or resolved, and CMake
chooses the compiler, so a CMake build's report names the CMake and is silent about the thing that
did the work. That is a deliberate narrowing rather than an oversight.

## One Windows limit worth knowing before you hit it

**A deeply nested checkout fails in MSBuild rather than in daukle.** The generated tree adds roughly
180 characters under your project (`build/daukle/cmake/_b/CMakeFiles/CMakeScratch/TryCompile-…`), and
MSBuild's FileTracker writes log files below that. Past `MAX_PATH` it reports
`FTK1011: could not create the new file tracking log file` seven times and CMake says
"Configuring incomplete", none of which mentions a path length. Measured while writing this example:
the same project failed under a 120-character parent and passed under a short one. Keep the checkout
near the root of a drive, or use another generator.

## What this example cannot show

**More than one target.** The modelled surface is one executable or one library. A project with an
application and a CLI beside it does not fit yet.

## The one file that is a harness input rather than part of the example

`needs-tools` marks this example as one that provisions real tools, which the harness skips unless
`DAUKLE_EXAMPLE_E2E=1` is set. CI sets it on every runner. The `console` block above is **executed**
rather than decorative: its `$ ` line is run and the line beneath it must appear in the output, so
the command and its result cannot drift apart the way a separate expectation file did.

**There is no committed executable here, and nothing is missing.** `cmake:run` really does build and
run the program; `build/` is gitignored, which is the only reason you cannot see the result in the
repository.
