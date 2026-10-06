#!/bin/sh
# Every pinned digest, against the cmake-<version>-SHA-256.txt Kitware
# publishes beside the assets.
#
# The e2e cases provision ONE CMake, because each is tens of megabytes. That
# leaves every other row asserted by nothing, and a transcribed digest is
# exactly the kind of claim this project keeps finding wrong. This covers all
# six rows of every release for one small GET per release.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
table="$root/lib/cmakes.lua"

if [ "${DAUKLE_CMAKE_E2E:-}" != "1" ]; then
  echo "skip pins: set DAUKLE_CMAKE_E2E=1 to check the pins against Kitware" >&2
  exit 0
fi

releases=$(sed -n 's/^  \["\([0-9][0-9.]*\)"\] = "\([0-9][0-9.]*\)",$/\1 \2/p' "$table")
if [ -z "$releases" ]; then
  echo "pins: no releases parsed out of lib/cmakes.lua, which is itself the failure" >&2
  exit 1
fi

# The asset each host key maps to, spelled the way lib/cmakes.lua spells it. A
# key here that the table does not carry, or a row there that this does not
# name, is caught by the per-release count below.
asset_for() {
  case "$1" in
    linux/x86_64)    echo "cmake-$2-linux-x86_64.tar.gz" ;;
    linux/aarch64)   echo "cmake-$2-linux-aarch64.tar.gz" ;;
    macos/x86_64)    echo "cmake-$2-macos-universal.tar.gz" ;;
    macos/aarch64)   echo "cmake-$2-macos-universal.tar.gz" ;;
    windows/x86_64)  echo "cmake-$2-windows-x86_64.zip" ;;
    windows/aarch64) echo "cmake-$2-windows-arm64.zip" ;;
    *) echo "" ;;
  esac
}

failed=0
checked=0
# No pipeline anywhere below: a `while read` fed by one runs in a subshell on
# every POSIX sh and loses the counters, leaving a check that is always green.
old_ifs=$IFS
IFS='
'
for release in $releases; do
  IFS=$old_ifs
  version=${release%% *}
  full=${release##* }

  published=$(curl -sSL --fail \
    "https://github.com/Kitware/CMake/releases/download/v$full/cmake-$full-SHA-256.txt" \
    2>/dev/null || true)
  if [ -z "$published" ]; then
    echo "FAIL $version: no SHA-256.txt for $full" >&2
    failed=$((failed + 1))
    IFS='
'
    continue
  fi

  rows=$(sed -n "/\[\"$version\"\] = {/,/^  },$/p" "$table" |
         sed -n 's/^    \["\([a-z0-9_\/]*\)"\][ ]*= "\([0-9a-f]\{64\}\)",$/\1 \2/p')
  count=0
  IFS='
'
  for row in $rows; do
    IFS=$old_ifs
    key=${row%% *}
    pinned=${row##* }
    asset=$(asset_for "$key" "$full")
    if [ -z "$asset" ]; then
      echo "FAIL $version $key: this check knows no asset for that host key" >&2
      failed=$((failed + 1))
    else
      want=$(echo "$published" | awk -v a="$asset" '$2 == a { print $1 }')
      if [ -z "$want" ]; then
        echo "FAIL $version $key: $asset is in no published SHA-256.txt line" >&2
        failed=$((failed + 1))
      elif [ "$want" != "$pinned" ]; then
        echo "FAIL $version $key: pinned $pinned, Kitware publishes $want" >&2
        failed=$((failed + 1))
      else
        checked=$((checked + 1))
      fi
    fi
    count=$((count + 1))
    IFS='
'
  done
  IFS=$old_ifs

  if [ "$count" -ne 6 ]; then
    echo "FAIL $version: $count host rows parsed, expected 6; a row this cannot read is a row" \
         "nothing checks" >&2
    failed=$((failed + 1))
  fi
  IFS='
'
done
IFS=$old_ifs

echo "$checked pinned CMake digests match Kitware, $failed failed"
[ "$failed" -eq 0 ]
