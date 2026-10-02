# cmake-cpp-executable

The same managed toolchain as `cmake-c-executable`, in C++, and with two keys that example does not
use. Read that one first; this one only shows what changes.

```
daukle cmake:run      # prints "hello from daukle"
```

## How this copy differs from your project

**It points at the working tree.** The manifest here says `cmake = "./plugins/cmake"` so that this
repository's suite tests the plugin as it stands, and a red example means a real defect rather than
a stale release. A real project names a pinned resolver and `coordinate = "daukle/cmake@^1.0.1"`
instead. Nothing vendors a copy of the plugin either way.

## What changes

**`language = "c++"` changes the default source globs**, from `src/*.c` to `src/*.cpp`, `src/*.cc`
and `src/*.cxx`. It also changes which CMake `LANGUAGES` the generated project declares, so the
generated file is C++ from its first line rather than C with a C++ file in it.

**`standard = 20` becomes `CXX_STANDARD`**, not `C_STANDARD`. One key, two meanings depending on
`language`, which is the kind of thing worth seeing in a generated file rather than trusting.

**`defines` is proved rather than asserted.** `src/main.cpp` prints a different sentence under
`#else`, so a `defines` list that silently failed to reach the compiler would change the output and
fail this example rather than passing quietly. A test that cannot fail is the failure mode this
repository is most careful about.

## The two `.txt` files, which are harness inputs rather than part of the example

`task.txt` and `expect-output.txt` are read by `test/run.sh`, not by daukle. `task.txt` holds the
one task CI runs here, `cmake:run`, and `expect-output.txt` the clause its output must contain,
`hello from daukle`. They sit beside the example rather than in `test/` so each example
carries its own expectations. An example with no `task.txt` is checked for its generated files
and never run.

**There is no committed executable here, and nothing is missing.** `cmake:run` really does build and
run the program; `build/` is gitignored, which is the only reason you cannot see the result in the
repository.
