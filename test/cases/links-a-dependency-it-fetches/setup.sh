#!/bin/sh
set -eu

# Beside the sandbox rather than inside it: daukle refuses a generated file
# that carries the project root, and the url lands verbatim in CMakeLists.txt.
# The name leads with dep- rather than trailing it, because the root is matched
# as a substring and a sandbox-named suffix would still carry it.
archive="$(cd .. && pwd)/dep-$(basename "$(pwd)").tar.gz"
tar -czf "$archive" -C dep .

if command -v sha256sum >/dev/null 2>&1; then
  digest=$(sha256sum "$archive" | cut -d' ' -f1)
else
  digest=$(shasum -a 256 "$archive" | cut -d' ' -f1)
fi

# CMake reads a local archive by path, and on Windows it needs the drive-letter
# form; the file:// spelling is not equivalent there and is not accepted.
case $(uname -s) in
  MINGW*|MSYS*|CYGWIN*) archive=$(cygpath -m "$archive") ;;
esac

sed -e "s|@URL@|$archive|" -e "s|@SHA256@|$digest|" \
    producer/daukle.toml.in > producer/daukle.toml
