# cmake-c-executable

A managed C project. The repository holds `daukle.toml` and `src/` and **no `CMakeLists.txt`**.
daukle downloads CMake, verifies it against a digest the plugin pins, generates one
`CMakeLists.txt` into `build/daukle/cmake/`, and runs CMake over it.

```
daukle sync           # generates build/daukle/cmake/CMakeLists.txt and nothing in your tree
daukle cmake:run      # configures, builds and runs, printing "hello from daukle"
```

## How this copy differs from your project

**It points at the working tree.** The manifest here says `cmake = "./plugins/cmake"` so that this
repository's suite tests the plugin as it stands, and a red example means a real defect rather than
a stale release. A real project names a pinned resolver and a coordinate instead:

```toml
[resolvers.github]
url = "https://raw.githubusercontent.com/daukle/daukle/<commit>/plugins/github-releases.lua"
sha256 = "..."

[plugins]
cmake = { resolver = "github", coordinate = "daukle/cmake@^1.0.1" }
```

Nothing vendors a copy of the plugin either way.

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

## The two `.txt` files, which are harness inputs rather than part of the example

`task.txt` and `expect-output.txt` are read by `test/run.sh`, not by daukle. `task.txt` holds the
one task CI runs here, `cmake:run`, and `expect-output.txt` the clause its output must contain,
`hello from daukle`. They sit beside the example rather than in `test/` so each example
carries its own expectations. An example with no `task.txt` is checked for its generated files
and never run.

**There is no committed executable here, and nothing is missing.** `cmake:run` really does build and
run the program; `build/` is gitignored, which is the only reason you cannot see the result in the
repository.
