# cmake-cpp-executable

The same managed toolchain as `cmake-c-executable`, in C++, and with two keys that example does not
use. Read that one first; this one only shows what changes.

```console
$ daukle cmake:run
hello from daukle
```

## This example is exactly what your project would hold

It names a pinned resolver and `coordinate = "daukle/cmake@^1.0.0"`, so the directory can be copied
anywhere and `daukle sync` works. Nothing vendors a copy of the plugin. The suite runs it twice,
once as committed against the published release and once with this repository's working tree staged
over a copy.

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

## The one file that is a harness input rather than part of the example

`needs-tools` marks this example as one that provisions real tools, which the harness skips unless
`DAUKLE_EXAMPLE_E2E=1` is set. CI sets it on every runner. The `console` block above is **executed**
rather than decorative, which is what makes the `defines` claim above a real assertion.

**There is no committed executable here, and nothing is missing.** `cmake:run` really does build and
run the program; `build/` is gitignored, which is the only reason you cannot see the result in the
repository.
