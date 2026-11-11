#!/bin/sh
# Every case is run against a real daukle, because this plugin's output is a
# generated file daukle writes and a real CMake consumes, and a stub of either
# would be testing the stub.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work="$root/test/.work"

daukle=${DAUKLE:-}
if [ -z "$daukle" ]; then
  for candidate in \
    "$root/.daukle/build/daukle" \
    "$root/.daukle/build/daukle.exe" \
    "$root/.daukle/build/Release/daukle.exe" \
    "$root/.daukle/build/Debug/daukle.exe"
  do
    [ -x "$candidate" ] && daukle=$candidate && break
  done
fi
if [ -z "$daukle" ] || [ ! -x "$daukle" ]; then
  echo "no daukle binary: set DAUKLE, or check out daukle/daukle into .daukle and build it" >&2
  exit 1
fi

passed=0
failed=0
skipped=0

fail() {
  echo "FAIL $1: $2" >&2
  failed=$((failed + 1))
}

# This plugin is multi-file, so the whole plugin directory is staged rather
# than the single plugin.lua the other repositories copy.
stage_plugin() {
  mkdir -p "$1/plugins/cmake"
  cp "$root/plugin.lua" "$1/plugins/cmake/plugin.lua"
  if [ -d "$root/lib" ]; then
    cp -R "$root/lib" "$1/plugins/cmake/lib"
  fi
}

MANIFEST_CHECK='
import sys
sections, current = [], []
for line in open(sys.argv[1], encoding="utf-8").read().splitlines():
    if line.startswith("["):
        sections.append(current)
        current = []
    current.append(line)
sections.append(current)
paragraphs = [[]]
for line in open(sys.argv[2], encoding="utf-8").read().splitlines():
    if line.strip():
        paragraphs[-1].append(line)
    elif paragraphs[-1]:
        paragraphs.append([])
paragraphs = [paragraph for paragraph in paragraphs if paragraph]
for paragraph in paragraphs:
    wanted = [line for line in paragraph if not line.startswith("!")]
    refused = [line[1:] for line in paragraph if line.startswith("!")]
    carrying = [section for section in sections if all(line in section for line in wanted)]
    if (wanted and not carrying) or any(line.startswith(prefix) for section in carrying for line in section for prefix in refused):
        print(" / ".join(paragraph))
        sys.exit(1)
'

outputs_carry_clauses() {
  clauses=$1
  shift
  if [ -f "$case_dir/$clauses" ]; then
    if ! grep -q . "$case_dir/$clauses"; then
      fail "$name" "$clauses is empty, so this case asserts nothing"
      return 1
    fi
    while IFS= read -r clause || [ -n "$clause" ]; do
      [ -n "$clause" ] || continue
      if ! grep -qF "$clause" "$@"; then
        fail "$name" "output does not carry: $clause"
        return 1
      fi
    done < "$case_dir/$clauses"
  fi
  return 0
}

manifest_carries_clauses() {
  [ -f "$case_dir/expect-manifest.txt" ] || return 0
  if ! grep -q . "$case_dir/expect-manifest.txt"; then
    fail "$name" "expect-manifest.txt is empty, so this case asserts nothing"
    return 1
  fi
  if [ ! -f "$sandbox/daukle.toml" ]; then
    fail "$name" "expected daukle.toml, which the migration did not write"
    return 1
  fi
  python=$(working_python) || { fail "$name" "no python3 or python that runs"; return 1; }
  if ! missing=$("$python" -c "$MANIFEST_CHECK" "$sandbox/daukle.toml" "$case_dir/expect-manifest.txt"); then
    fail "$name" "daukle.toml does not match, in one table: $missing"
    return 1
  fi
  return 0
}

working_python() {
  for candidate in python3 python; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    "$candidate" -c 'import sys' >/dev/null 2>&1 && { echo "$candidate"; return 0; }
  done
  return 1
}

PLUGIN_SERVER='
import functools, http.server, os, sys
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=sys.argv[1])
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
with open(sys.argv[2] + ".tmp", "w") as out:
    out.write(str(server.server_port))
os.replace(sys.argv[2] + ".tmp", sys.argv[2])
server.serve_forever()
'

# daukle migrate finds a plugin only through a catalog, whose asset is pinned
# by url and sha256 and taken over https or loopback http alone. So the plugin
# is packed exactly as publish.yml packs it and served from 127.0.0.1, once per
# run. Copied from daukle/node's harness, which measured both constraints.
serve_plugin() {
  [ -n "${catalog:-}" ] && return 0
  python=$(working_python) || { fail "$name" "no python3 or python that runs"; return 1; }
  asset_dir="$work/asset"
  mkdir -p "$asset_dir"
  # COPYFILE_DISABLE and ustar keep macOS bsdtar from adding AppleDouble or pax
  # members, and core's tar reader takes only regular files and directories.
  packed="$work/plugin.tar"
  (cd "$root" && COPYFILE_DISABLE=1 tar --format=ustar -cf "$packed" plugin.lua lib/*.lua)
  digest=$(sha256sum "$packed" 2>/dev/null | cut -d' ' -f1)
  [ -n "$digest" ] || digest=$(shasum -a 256 "$packed" | cut -d' ' -f1)
  # Served under its own digest because core caches a plugin by its url, and a
  # port an earlier run used would hand back that run's lib/.
  mkdir -p "$asset_dir/$digest"
  mv "$packed" "$asset_dir/$digest/plugin.lua"
  port_file="$work/server-port"
  rm -f "$port_file"
  "$python" -c "$PLUGIN_SERVER" "$asset_dir" "$port_file" >"$work/server.log" 2>&1 &
  server=$!
  trap 'kill "$server" 2>/dev/null || true' EXIT
  port=
  for _ in $(seq 60); do
    [ -s "$port_file" ] && port=$(cat "$port_file") &&
      curl -fsS "http://127.0.0.1:$port/$digest/plugin.lua" -o /dev/null 2>/dev/null && break
    port=
    kill -0 "$server" 2>/dev/null || break
    sleep 1
  done
  if [ -z "$port" ]; then
    fail "$name" "the plugin server did not start, so no migrate case can run: $(cat "$work/server.log")"
    return 1
  fi
  catalog="$work/catalog.json"
  "$python" -c 'import json,sys; c=json.load(open(sys.argv[1])); c.update(id="cmake", asset={"url":sys.argv[2],"sha256":sys.argv[3]}); json.dump({"plugins":[c]}, open(sys.argv[4],"w"))' \
    "$root/catalog.json" "http://127.0.0.1:$port/$digest/plugin.lua" "$digest" "$catalog"
}

# One path per line in expect-file.txt that must exist after the run, and in
# expect-absent.txt that must not: what a migration moved aside and what it
# kept is asserted on the tree itself, never on the message that reports it.
tree_has_paths() {
  for list in expect-file.txt expect-absent.txt; do
    [ -f "$case_dir/$list" ] || continue
    if ! grep -q . "$case_dir/$list"; then
      fail "$name" "$list is empty, so this case asserts nothing"
      return 1
    fi
    while IFS= read -r wanted || [ -n "$wanted" ]; do
      [ -n "$wanted" ] || continue
      if [ "$list" = expect-file.txt ] && [ ! -e "$sandbox/$wanted" ]; then
        fail "$name" "expected $wanted, which the run did not leave"
        return 1
      fi
      if [ "$list" = expect-absent.txt ] && [ -e "$sandbox/$wanted" ]; then
        fail "$name" "$wanted is still there"
        return 1
      fi
    done < "$case_dir/$list"
  done
  return 0
}

# A migrate case asserts its exit code (expect-exit.txt), then what the output
# and the files it names carry and lack, with the same expect-output.txt,
# expect-contains.txt, expect-blocks.txt and expect-lacks.txt every other case
# uses, then expect-manifest.txt, then the paths it expects present and absent.
# A case with after-migrate then runs each daukle command it lists, in order,
# each of which must succeed, and their output must carry
# expect-after-output.txt: what proves a build still works once the migration
# moved the old files aside, which the migration's own proof ran before.
run_after_migrate() {
  [ -f "$case_dir/after-migrate" ] || return 0
  while IFS= read -r command || [ -n "$command" ]; do
    [ -n "$command" ] || continue
    if ! (cd "$sandbox" && "$daukle" $command >>after-stdout.txt 2>>after-stderr.txt </dev/null); then
      fail "$name" "after the migration, daukle $command failed"
      tail -n 30 "$sandbox/after-stderr.txt" >&2
      return 1
    fi
  done < "$case_dir/after-migrate"
  outputs_carry_clauses expect-after-output.txt "$sandbox/after-stdout.txt" "$sandbox/after-stderr.txt"
}

run_migrate_case() {
  serve_plugin || return 0
  status=0
  (cd "$sandbox" && "$daukle" migrate --catalog "$catalog" >stdout.txt 2>stderr.txt) || status=$?
  wanted=$(cat "$case_dir/expect-exit.txt")
  if [ "$status" -ne "$wanted" ]; then
    fail "$name" "migrate exited $status, wanted $wanted"
    echo "--- stdout" >&2
    tail -n 30 "$sandbox/stdout.txt" >&2
    echo "--- stderr" >&2
    tail -n 30 "$sandbox/stderr.txt" >&2
    return 0
  fi
  outputs_carry_clauses expect-output.txt "$sandbox/stdout.txt" "$sandbox/stderr.txt" || return 0
  manifest_carries_clauses || return 0
  tree_has_paths || return 0
  run_after_migrate || return 0
  passed=$((passed + 1))
}


run_case() {
  case_dir=$1
  name=$(basename "$case_dir")

  if [ -f "$case_dir/migrate" ]; then
    if [ "$(uname -s)" != "Linux" ] && [ "${DAUKLE_CMAKE_E2E:-}" != "1" ]; then
      echo "skip $name: set DAUKLE_CMAKE_E2E=1 to run it here" >&2
      skipped=$((skipped + 1))
      return
    fi
    sandbox="$work/$name"
    rm -rf "$sandbox"
    mkdir -p "$(dirname "$sandbox")"
    cp -R "$case_dir" "$sandbox"
    rm -f "$sandbox/migrate" "$sandbox/expect-exit.txt" "$sandbox/expect-manifest.txt"           "$sandbox/expect-output.txt" "$sandbox/expect-file.txt" "$sandbox/expect-absent.txt"           "$sandbox/after-migrate" "$sandbox/expect-after-output.txt"
    run_migrate_case
    return
  fi

  # daukle.lua is included because core accepts one as the PRIMARY manifest
  # when no daukle.toml sits beside it, and a chunk that parses the manifest
  # has to survive a format daukle.parse refuses to run.
  for manifest in "$case_dir"/daukle*.toml "$case_dir"/daukle.lua; do
    [ -f "$manifest" ] || continue
    manifest_name=$(basename "$manifest")
    sandbox="$work/$name-$manifest_name"
    rm -rf "$sandbox"
    mkdir -p "$(dirname "$sandbox")"
    cp -R "$case_dir" "$sandbox"
    rm -rf "$sandbox/expected" "$sandbox/expect-error.txt" \
           "$sandbox/task.txt" "$sandbox/produces.txt" \
           "$sandbox/expect-task-error.txt" "$sandbox/expect-output.txt" \
           "$sandbox/expect-tasks.txt" "$sandbox/expect-no-tasks.txt" "$sandbox/rerun"            "$sandbox/expect-plan.txt" "$sandbox/expect-plan-absent.txt"
    stage_plugin "$sandbox"

    # A case whose manifest has to carry a digest of something on disk builds
    # that something here instead of committing it, because git rewriting a
    # line ending would silently stop the digest matching.
    if [ -f "$sandbox/setup.sh" ]; then
      if ! (cd "$sandbox" && sh ./setup.sh >setup-log.txt 2>&1); then
        fail "$name/$manifest_name" "setup.sh failed"
        sed -n '1,20p' "$sandbox/setup-log.txt" >&2
        continue
      fi
      rm -f "$sandbox/setup-log.txt"
    fi

    if [ -f "$case_dir/expect-error.txt" ]; then
      if (cd "$sandbox" && "$daukle" sync "$manifest_name" >stdout.txt 2>stderr.txt); then
        fail "$name/$manifest_name" "expected a failure, got success"
        continue
      fi
      clause=$(cat "$case_dir/expect-error.txt")
      if [ -z "$clause" ]; then
        fail "$name/$manifest_name" "the expected-clause file is empty, so this case asserts nothing"
        continue
      fi
      if ! grep -qF "$clause" "$sandbox/stderr.txt" "$sandbox/stdout.txt"; then
        fail "$name/$manifest_name" "message does not carry: $clause"
        continue
      fi
      passed=$((passed + 1))
      continue
    fi

    # What `daukle tasks` NAMES, which needs no CMake and no compiler and so
    # runs on every host. The tasks a target produces are registered when the
    # chunk loads, long before anything is provisioned, so gating that assertion
    # behind a 100 MB download would leave the registration proved only where
    # the whole toolchain already works.
    if [ -f "$case_dir/expect-tasks.txt" ]; then
      if ! (cd "$sandbox" && "$daukle" tasks >tasks.txt 2>tasks-stderr.txt); then
        cat "$sandbox/tasks-stderr.txt" >&2
        fail "$name/$manifest_name" "daukle tasks failed"
        continue
      fi
      missing=
      while IFS= read -r wanted; do
        [ -n "$wanted" ] || continue
        grep -qF "$wanted" "$sandbox/tasks.txt" || missing="$missing $wanted"
      done < "$case_dir/expect-tasks.txt"
      if [ -n "$missing" ]; then
        cat "$sandbox/tasks.txt" >&2
        fail "$name/$manifest_name" "daukle tasks does not name:$missing"
        continue
      fi
      # A presence-only assertion cannot catch a task that should not be there,
      # which is how "and no run-greeter" stayed a sentence rather than a check.
      if [ -f "$case_dir/expect-no-tasks.txt" ]; then
        present=
        while IFS= read -r unwanted; do
          [ -n "$unwanted" ] || continue
          grep -qF "$unwanted" "$sandbox/tasks.txt" && present="$present $unwanted"
        done < "$case_dir/expect-no-tasks.txt"
        if [ -n "$present" ]; then
          cat "$sandbox/tasks.txt" >&2
          fail "$name/$manifest_name" "daukle tasks names what it must not:$present"
          continue
        fi
      fi
      passed=$((passed + 1))
      continue
    fi

    if [ -f "$case_dir/task.txt" ]; then
      if [ "$manifest_name" != "daukle.toml" ]; then
        fail "$name/$manifest_name" "a task case's manifest must be daukle.toml"
        continue
      fi
      # A task provisions a real CMake and needs a compiler and make on the
      # host, so a bare local run on a developer's machine does not pay for the
      # download unasked. CI sets DAUKLE_CMAKE_E2E on every runner, because the
      # macOS home layout and the Windows zip are exercised by nothing else.
      if [ "$(uname -s)" != "Linux" ] && [ "${DAUKLE_CMAKE_E2E:-}" != "1" ]; then
        echo "skip $name/$manifest_name: set DAUKLE_CMAKE_E2E=1 to run it here" >&2
        skipped=$((skipped + 1))
        continue
      fi
      task=$(cat "$case_dir/task.txt")
      if [ -f "$case_dir/expect-task-error.txt" ] && [ -f "$case_dir/produces.txt" ]; then
        fail "$name/$manifest_name" "a case carries both expect-task-error.txt and produces.txt; they are mutually exclusive"
        continue
      fi
      if [ -f "$case_dir/expect-task-error.txt" ]; then
        if (cd "$sandbox" && "$daukle" "$task" >stdout.txt 2>stderr.txt); then
          fail "$name/$manifest_name" "expected task $task to fail, got success"
          continue
        fi
        clause=$(cat "$case_dir/expect-task-error.txt")
        if [ -z "$clause" ]; then
          fail "$name/$manifest_name" "the expected-clause file is empty, so this case asserts nothing"
          continue
        fi
        if ! grep -qF "$clause" "$sandbox/stderr.txt" "$sandbox/stdout.txt"; then
          fail "$name/$manifest_name" "message does not carry: $clause"
          continue
        fi
        passed=$((passed + 1))
        continue
      fi
      if ! (cd "$sandbox" && "$daukle" "$task" >stdout.txt 2>stderr.txt); then
        fail "$name/$manifest_name" "task $task failed"
        sed -n '1,40p' "$sandbox/stderr.txt" >&2
        continue
      fi
      # A second run sees CMake's cache, which is where a line printed only on
      # first detection disappears; the output asserted is then the second run's.
      if [ -f "$case_dir/rerun" ] && ! (cd "$sandbox" && "$daukle" "$task" >stdout.txt 2>stderr.txt); then
        fail "$name/$manifest_name" "task $task failed on its second run"
        sed -n '1,40p' "$sandbox/stderr.txt" >&2
        continue
      fi
      if ! plan_carries_lines "$case_dir" "$sandbox" "$name/$manifest_name"; then
        continue
      fi
      # An example asserts on what the task PRINTED, which is what a reader
      # of the example came for. A test case asserts on the files produced.
      if [ -f "$case_dir/expect-output.txt" ]; then
        clause=$(cat "$case_dir/expect-output.txt")
        if [ -z "$clause" ]; then
          fail "$name/$manifest_name" "the expected-clause file is empty, so this case asserts nothing"
          continue
        fi
        if ! grep -qF "$clause" "$sandbox/stdout.txt" "$sandbox/stderr.txt"; then
          fail "$name/$manifest_name" "task $task printed no \"$clause\""
          continue
        fi
        passed=$((passed + 1))
        continue
      fi
      if ! grep -q . "$case_dir/produces.txt"; then
        fail "$name/$manifest_name" "produces.txt lists nothing, so this case asserts nothing"
        continue
      fi
      produced_ok=0
      while IFS= read -r produced || [ -n "$produced" ]; do
        [ -z "$produced" ] && continue
        # Expanded as a glob, because the path a build writes its binary to is
        # generator-dependent and a case must be able to name it on every
        # platform. An unmatched glob stays literal and fails the -s below.
        found=0
        for candidate in $sandbox/$produced; do
          [ -s "$candidate" ] && found=1 && break
        done
        if [ "$found" -eq 0 ]; then
          fail "$name/$manifest_name" "$produced is missing or empty"
          produced_ok=1
        fi
      done < "$case_dir/produces.txt"
      [ "$produced_ok" -eq 0 ] && passed=$((passed + 1))
      continue
    fi

    # Twice, because applying twice must equal applying once for every case,
    # not only for the one a test remembered to say it about.
    if ! (cd "$sandbox" && "$daukle" sync "$manifest_name" >/dev/null 2>&1); then
      fail "$name/$manifest_name" "sync failed"
      continue
    fi
    if ! compare_expected "$case_dir" "$sandbox" "$name/$manifest_name (first)"; then
      continue
    fi
    if ! (cd "$sandbox" && "$daukle" sync "$manifest_name" >/dev/null 2>&1); then
      fail "$name/$manifest_name" "second sync failed"
      continue
    fi
    if ! compare_expected "$case_dir" "$sandbox" "$name/$manifest_name (second)"; then
      continue
    fi
    passed=$((passed + 1))
  done
}

# What a task's plan.txt must hold and must not, line for line: the plan is the file a migration's
# proof compares, so a case asserts the lines a reader of the proof would look for.
plan_carries_lines() {
  plan="$2/build/daukle/cmake/plan.txt"
  for list in expect-plan.txt expect-plan-absent.txt; do
    [ -f "$1/$list" ] || continue
    if ! grep -q . "$1/$list"; then
      fail "$3" "$list is empty, so this case asserts nothing"
      return 1
    fi
    if [ ! -f "$plan" ]; then
      fail "$3" "the task wrote no plan.txt"
      return 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      if [ "$list" = expect-plan.txt ] && ! grep -qxF -- "$line" "$plan"; then
        fail "$3" "plan.txt lacks: $line"
        return 1
      fi
      if [ "$list" = expect-plan-absent.txt ] && grep -qxF -- "$line" "$plan"; then
        fail "$3" "plan.txt holds: $line"
        return 1
      fi
    done < "$1/$list"
  done
  return 0
}

compare_expected() {
  expected_root=$1/expected
  actual_root=$2
  label=$3
  ok=0
  # An empty expected/ would compare nothing and pass, which is the one way a
  # case can look green while asserting nothing at all.
  if [ -z "$(cd "$expected_root" && find . -type f)" ]; then
    fail "$label" "expected/ holds no files, so this case asserts nothing"
    return 1
  fi
  for expected in $(cd "$expected_root" && find . -type f); do
    if ! cmp -s "$expected_root/$expected" "$actual_root/$expected"; then
      fail "$label" "$expected differs"
      diff -u "$expected_root/$expected" "$actual_root/$expected" >&2 || true
      ok=1
    fi
  done
  return $ok
}

rm -rf "$work"
for case_dir in "$root"/test/cases/*/; do
  [ -d "$case_dir" ] || continue
  run_case "${case_dir%/}"
done

echo "$passed passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
