#!/usr/bin/env bash
# L3 -- the e2e fixture layer (docs/testing-strategy.md Step 3).
#
# Drives every e2e/ fixture through the lifecycle a user actually experiences,
# with a REAL compiled binary:
#
#   pub get -> compile -> db migrate generate -> db migrate apply -> serve
#           -> HTTP assertions -> restart -> re-assert -> clean shutdown
#
# The assertions are in tool/ci/e2e/drive.dart and they are on RESPONSE BODIES
# AND DATABASE CONTENTS, never on exit codes. Every bug this layer exists for
# was invisible to "the command exited 0":
#
#   #21      a leading-zero `Eq` -- closed wrongly once on a green SQL-builder
#            unit test; the real driver caught it
#   551081f  a CastList cannot cross an isolate, so In/NotIn were broken on
#            EVERY released binary
#   02cfcef  the worker's own published copy of the same serializer -- needed a
#            second published release, because no CLI release can reach it
#   a16b499  an update that read itself back by replaying its own where: the
#            write landed and the RESPONSE was wrong
#
# WHAT MODE MEANS HERE, AND WHY IT IS NOT `ZONAI_FORCE_WORKERS`
# ------------------------------------------------------------
# docs/testing-strategy.md prescribes running each mutation fixture twice --
# linked, then ZONAI_FORCE_WORKERS=1. Measured against these fixtures that is
# the SAME configuration twice: e2e/* depend on `zonai_schema` and not on
# `zonai`, so a bare CLI cannot link a project runtime against them at all.
# `zonai version` reports `Ops/rules: worker IPC` with and without the flag.
#
# The axis that actually separates the bugs above is the TRANSPORT, and Mailman
# has two that accept different things (551081f's message says so outright):
#
#   process   framed MessagePack to .zonai/executables/*.exe -- bytes, so any
#             List implementation serializes fine, and 551081f is GREEN here
#   isolate   Isolate.spawnUri on .zonai/executables/*.aot, then
#             SendPort.send(message) -- the object graph itself, which may only
#             carry plain List/Map. This is what a release spawns and the only
#             mode in which 551081f and 02cfcef fail.
#
# So the modes below are `process` and `isolate`, both non-optional, and
# `isolate` is the one that matters. See also assert_isolate_transport below:
# a snapshot that will not spawn falls back to `process` with nothing but a
# warning in the log, which would make the whole isolate leg vacuous while
# still reporting green.
#
# Usage:
#   run_e2e.sh [binary] [fixture...]
#
# Environment:
#   ZONAI_E2E_BINARY        path to a compiled zonai (default: build/zonai)
#   ZONAI_E2E_PORT          first port to use (default: 8757)
#   ZONAI_E2E_HEALTH_TIMEOUT seconds to wait for /health (default: 90)
#
# There is deliberately no "make an assertion fail" switch. A gate with a
# built-in way to lie is worse than one nobody has proved can fail; the proof
# for this one is a recorded pair of runs against a one-line edit to an
# expected value in drive.dart, captured under
# .showrunner/scratch/orchestrator-e2e-layer/.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

health_timeout="${ZONAI_E2E_HEALTH_TIMEOUT:-90}"
next_port="${ZONAI_E2E_PORT:-8757}"

# Fixtures whose HTTP suites live in tool/ci/e2e/drive.dart. build_smoke is
# NOT here: it is driven by verify_build_command.sh, which already builds a
# deployable bundle and serves out of it. Duplicating that would pay for two
# more full worker compiles to assert less.
served_fixtures=(
  crud_matrix
  admin_password_update_repro
  signup_backfill_repro
  concurrency_repro
)

# Declared, not silently absent. external_auth provisions a user from a
# Supabase-shaped HS256 JWT, and the fixture's own lib/src/config/app_config.dart
# carries no `externalIdps` entry -- its in-repo test injects one via
# ConfigResolver.fixed, which nothing outside the process can do. Driving it
# over HTTP needs that entry in the fixture AND an HMAC-SHA256 signer here;
# drive.dart imports nothing outside the SDK, so it has no HMAC. Covered
# in-process by apps/zonai/test/e2e/external_auth_provisioning_e2e_test.dart
# and NOT by this layer.
skipped_fixtures=(
  "external_auth: needs an externalIdps entry in the fixture config and an HMAC-SHA256 signer in drive.dart"
)

modes=(process isolate)

# ---------------------------------------------------------------------------
# Reporting. Every failure names the fixture and the assertion, because a
# sibling CI job is wired to this contract: exit 0 pass, non-zero fail.
# ---------------------------------------------------------------------------
current_fixture="-"
current_mode="-"

fail() {
  echo "" >&2
  echo "E2E FAIL" >&2
  echo "  fixture:   ${current_fixture}" >&2
  echo "  mode:      ${current_mode}" >&2
  echo "  assertion: $1" >&2
  shift
  for line in "$@"; do
    echo "  ${line}" >&2
  done
  echo "" >&2
  exit 1
}

step() { echo "-- [${current_fixture}/${current_mode}] $*"; }

# ---------------------------------------------------------------------------
# The binary. Resolved, never built: `test cli` fails loudly rather than
# passing against a stale lib/gen for the same reason, and a layer that
# quietly compiles 40MB of Dart when you asked it to run tests is a layer
# nobody can reason about the runtime of.
# ---------------------------------------------------------------------------
resolve_binary() {
  local candidate="${1:-}"
  if [ -z "$candidate" ]; then
    candidate="${ZONAI_E2E_BINARY:-}"
  fi
  if [ -z "$candidate" ]; then
    if [ -x "${repo_root}/build/zonai.exe" ]; then
      candidate="${repo_root}/build/zonai.exe"
    else
      candidate="${repo_root}/build/zonai"
    fi
  fi

  if [ ! -f "$candidate" ]; then
    echo "run_e2e.sh: no compiled zonai binary at ${candidate}" >&2
    echo "" >&2
    echo "  This layer drives a REAL compiled binary on purpose -- every bug it" >&2
    echo "  guards was invisible from source. Build one first:" >&2
    echo "" >&2
    echo "    sip run zonai compile" >&2
    echo "" >&2
    echo "  or point it at one: ZONAI_E2E_BINARY=/path/to/zonai" >&2
    exit 1
  fi

  [ -x "$candidate" ] || chmod +x "$candidate"
  # Absolute: every command below runs with cwd inside a fixture.
  echo "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
}

# ---------------------------------------------------------------------------
# The toolchain that builds the worker snapshots must be the one that built the
# host binary, or Isolate.spawnUri refuses the snapshot ("Wrong full snapshot
# version") and Mailman falls back to the process transport -- silently, apart
# from one warn line.
#
# `zonai compile` picks its `dart` through raindrop's DartExecutable.resolve,
# which prefers zonai.yaml's dartSdkPath, then DART_SDK/DART_HOME, then FVM and
# ~/flutter installs, and only then the `dart` on PATH -- so it can easily
# differ from the SDK that ran `sip run zonai compile` to produce build/zonai.
#
# Measured on macOS 2026-08-14, repeatedly: with DART_SDK unset the .aot files
# came out with a snapshot version the compiled host refused, and Mailman fell
# back to the process transport with one warn line. With DART_SDK exported as
# below they spawn. What was NOT established is WHICH sdk produced the bad
# snapshot -- pointing DART_SDK at either SDK present on that machine gave a
# spawnable one, and only leaving it unset reproduced the mismatch. So this is
# a precaution with a measured effect rather than a diagnosed fix, and
# assert_isolate_transport is what makes the outcome visible either way.
# ---------------------------------------------------------------------------
pin_dart_sdk() {
  local dart_path
  dart_path="$(command -v dart || true)"
  if [ -z "$dart_path" ]; then
    echo "run_e2e.sh: no \`dart\` on PATH -- \`zonai compile\` needs one to" >&2
    echo "  build the worker executables and AOT snapshots." >&2
    exit 1
  fi
  DART_SDK="$(cd "$(dirname "$dart_path")/.." && pwd)"
  export DART_SDK
  echo "Pinned DART_SDK=${DART_SDK} ($(dart --version 2>&1))"
}

# ---------------------------------------------------------------------------
# Fixture lifecycle
# ---------------------------------------------------------------------------

# `--no-version-check`/`--no-schema-version-check` rather than rewriting each
# fixture's zonai.yaml: the version pin is not what this layer is testing, and
# a gate that edits tracked files to pass leaves the tree dirty for whoever
# runs it next.
zonai() {
  "$binary" "$@" --no-version-check --no-schema-version-check
}

fixture_prepare() {
  local fixture="$1"
  local dir="${repo_root}/e2e/${fixture}"

  [ -d "$dir" ] || fail "the fixture directory exists" "expected:  ${dir}" "actual:    missing"

  cd "$dir"

  # Start from nothing: a stale .zonai/ can satisfy assertions that the
  # commands below were supposed to earn. (e2e/build_smoke/.zonai and its
  # pubspec.lock are gitignored for this reason -- see .gitignore:64-71 -- and
  # the same is true of every fixture once this script has run.)
  rm -rf .zonai

  step "dart pub get"
  dart pub get >/dev/null

  step "zonai compile (workers + AOT snapshots)"
  zonai compile

  step "zonai db migrate generate"
  zonai db migrate generate --name initialize

  if ! ls .zonai/migrations/*.sql >/dev/null 2>&1; then
    fail "db migrate generate wrote a migration" \
      "expected:  at least one .zonai/migrations/*.sql" \
      "actual:    none"
  fi

  # The isolate transport has no snapshot to spawn without these, so its whole
  # leg would fall back to `process` and assert nothing new.
  local snapshot
  for snapshot in db_rules.aot db_operations.aot; do
    if [ ! -f ".zonai/executables/${snapshot}" ]; then
      fail "zonai compile produced ${snapshot}" \
        "expected:  .zonai/executables/${snapshot}" \
        "actual:    missing -- the isolate transport would silently fall back to the worker process, which is the configuration 551081f and 02cfcef were both green in"
    fi
  done

  cd "$repo_root"
}

fixture_reset_db() {
  local fixture="$1"
  cd "${repo_root}/e2e/${fixture}"
  # Each mode gets a fresh database: the suites mutate and delete, so a second
  # mode reading the first one's leftovers proves nothing about itself.
  rm -rf .zonai/data
  step "zonai db migrate apply (fresh database)"
  zonai db migrate apply
  cd "$repo_root"
}

# ---------------------------------------------------------------------------
# serve
# ---------------------------------------------------------------------------
serve_pid=""
serve_log=""

# The server binds IPv6-any and, measured on macOS 2026-08-14, does NOT then
# answer on 127.0.0.1 -- only [::1] and localhost. verify_build_command.sh and
# verify_compat.sh both probe all three for this reason; so does this.
resolve_base_url() {
  local port="$1" url
  for url in "http://localhost:${port}" "http://[::1]:${port}" "http://127.0.0.1:${port}"; do
    if curl -sf --max-time 2 "${url}/health" >/dev/null 2>&1; then
      echo "$url"
      return 0
    fi
  done
  return 1
}

serve_start() {
  local fixture="$1" mode="$2" port="$3"
  serve_log="${repo_root}/e2e/${fixture}/.zonai/serve-${mode}-${port}.log"

  cd "${repo_root}/e2e/${fixture}"
  step "zonai serve --port ${port} (ZONAI_WORKER_TRANSPORT=${mode})"

  # `--release`: no file watchers and no recompiling, so the process under test
  # is the one `compile` produced and nothing changes underneath the assertions.
  ZONAI_WORKER_TRANSPORT="$mode" "$binary" serve \
    --port "$port" --release --log verbose \
    --no-version-check --no-schema-version-check >"$serve_log" 2>&1 &
  serve_pid=$!
  cd "$repo_root"

  local deadline=$(( $(date +%s) + health_timeout ))
  base_url=""
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if ! kill -0 "$serve_pid" 2>/dev/null; then
      wait "$serve_pid" 2>/dev/null || true
      serve_pid=""
      fail "serve stays up long enough to answer /health" \
        "expected:  a live server on port ${port}" \
        "actual:    the process exited; last lines of ${serve_log}:" \
        "$(tail -20 "$serve_log" 2>/dev/null || true)"
    fi
    if base_url="$(resolve_base_url "$port")"; then
      step "serving at ${base_url}"
      return 0
    fi
    sleep 0.5
  done

  fail "serve answers /health within ${health_timeout}s" \
    "expected:  200 from /health on 127.0.0.1, [::1] or localhost:${port}" \
    "actual:    no answer; last lines of ${serve_log}:" \
    "$(tail -20 "$serve_log" 2>/dev/null || true)"
}

serve_stop() {
  [ -n "$serve_pid" ] || return 0
  # `kill` then `kill -9`: on Windows (Git Bash) a signal to a native process
  # is best-effort, and a server still holding the sqlite file breaks the next
  # mode's `migrate apply` rather than this one's assertions.
  kill "$serve_pid" 2>/dev/null || true
  local deadline=$(( $(date +%s) + 15 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    kill -0 "$serve_pid" 2>/dev/null || break
    sleep 0.5
  done
  if kill -0 "$serve_pid" 2>/dev/null; then
    kill -9 "$serve_pid" 2>/dev/null || true
  fi
  wait "$serve_pid" 2>/dev/null || true
  serve_pid=""
}

cleanup() { serve_stop; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# The check that keeps the isolate leg from being vacuous.
#
# Mailman logs a warn and carries on when a snapshot will not spawn. Nothing
# else is observable: the process transport serves identically and answers
# every assertion in drive.dart. So this leg has to assert the transport it
# claims, or it is a second copy of the `process` leg wearing its name --
# which is exactly the configuration 551081f and 02cfcef shipped green in.
#
# Only RULES_EXE and OPERATIONS_EXE are checked. They are the only two workers
# `zonai compile` builds a snapshot for; config, crons, rate limits and
# extensions have no .aot and fall back by design, so demanding it of them
# would fail every run for a reason that is not a defect.
#
# It asserts the PRESENCE of "Started isolate worker" rather than the ABSENCE
# of a fallback line, and it runs AFTER the assertions rather than before. Both
# of those are corrections to a first version that could not fail:
#
#   - the rules and operations workers start LAZILY, on the first request that
#     needs them. Config and crons start at boot, so a log taken right after
#     /health answers mentions those two and nothing else -- an absence-of-
#     fallback check read that log and reported ok having observed nothing.
#     Measured 2026-08-14: with both .aot files deleted outright, the check
#     still passed.
#   - "no bad line" passes on an empty log. "this good line is there" cannot.
#
# Needs `--log verbose`: the line is logged at debug level.
# ---------------------------------------------------------------------------
assert_isolate_transport() {
  [ "$current_mode" = "isolate" ] || return 0

  local worker context
  for worker in RULES OPERATIONS; do
    if ! grep -qF "[${worker}_EXE]: Started isolate worker" "$serve_log"; then
      context="$(grep -E "\[${worker}_EXE\]" "$serve_log" 2>/dev/null | head -5 || true)"
      fail "the ${worker} worker really took the isolate transport" \
        "expected:  '[${worker}_EXE]: Started isolate worker' in ${serve_log}" \
        "actual:    absent. What that worker did log:" "${context:-(nothing -- it never started)}" \
        "why it is here: the process transport encodes messages to bytes" \
        "  first, so any List implementation serializes fine and 551081f /" \
        "  02cfcef are GREEN on it. Mailman logs a warn and carries on when a" \
        "  snapshot will not spawn, so a silent fallback would make this whole" \
        "  leg a second copy of the process leg while still reporting green." \
        "  Observed cause on macOS 2026-08-14: without DART_SDK pinned, the" \
        "  .aot came out with a snapshot version the compiled host refused" \
        "  ('Wrong full snapshot version') -- see pin_dart_sdk above. Which" \
        "  SDK produced it was NOT established: pointing DART_SDK at either" \
        "  SDK on that machine produced a spawnable snapshot, and only" \
        "  leaving it unset reproduced the mismatch. So pin_dart_sdk is a" \
        "  precaution with a measured effect, not a diagnosed fix, and this" \
        "  check is what makes the difference visible either way."
    fi
  done
  echo "  ok: RULES_EXE and OPERATIONS_EXE are on the isolate transport"
}

# ---------------------------------------------------------------------------
# drive.dart. Imports nothing outside the SDK, so no `pub get` of its own.
# ---------------------------------------------------------------------------
drive() {
  local fixture="$1" mode="$2" phase="$3"
  step "assertions (${phase})"
  if ! dart run "${repo_root}/tool/ci/e2e/drive.dart" \
    --fixture "$fixture" --base-url "$base_url" \
    --mode "$mode" --phase "$phase"; then
    fail "drive.dart's ${phase} assertions for ${fixture} pass" \
      "expected:  exit 0 (the named assertion above is the one that failed)" \
      "actual:    non-zero; server log: ${serve_log}"
  fi
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------
binary="$(resolve_binary "${1:-}")"
if [ "$#" -gt 0 ]; then shift; fi
requested=("$@")

echo "e2e layer: $("$binary" version --no-version-check --no-schema-version-check | tr '\n' ' ')"
echo "binary: ${binary}"
pin_dart_sdk
for note in "${skipped_fixtures[@]}"; do
  echo "SKIPPED (out loud) -- ${note}"
done
echo ""

should_run() {
  local fixture="$1" want
  [ "${#requested[@]}" -eq 0 ] && return 0
  for want in "${requested[@]}"; do
    [ "$want" = "$fixture" ] && return 0
  done
  return 1
}

# build_smoke first: it is the cheapest way to find out that `zonai build` is
# broken, and every other fixture below depends on the same compile path.
#
# One side effect worth knowing about before it surprises someone: this
# delegation rewrites `version:` in e2e/build_smoke/zonai.yaml to match
# VERSION, because verify_build_command.sh calls sync_playground_version.sh.
# That was harmless while the only caller was a CI job on a throwaway
# checkout; `sip run test e2e` is a contributor-facing command, so it now
# leaves one tracked line dirty after every VERSION bump. Left as-is rather
# than worked around here -- the fix belongs in verify_build_command.sh (save
# and restore, or drop the sync now that both callers pass
# --no-version-check), not in a caller papering over it.
if should_run build_smoke; then
  current_fixture="build_smoke"
  current_mode="build+bundle"
  step "delegating to verify_build_command.sh (build a bundle, serve out of it)"
  if ! bash "${repo_root}/tool/ci/verify_build_command.sh" "$binary" \
      "e2e/build_smoke" "$health_timeout"; then
    fail "zonai build produces a bundle that serves" \
      "expected:  verify_build_command.sh to exit 0" \
      "actual:    non-zero (its own output above names which check failed)"
  fi
  echo ""
fi

for fixture in "${served_fixtures[@]}"; do
  should_run "$fixture" || continue

  current_fixture="$fixture"
  current_mode="prepare"
  fixture_prepare "$fixture"

  for mode in "${modes[@]}"; do
    current_mode="$mode"
    port="$next_port"
    next_port=$(( next_port + 1 ))

    fixture_reset_db "$fixture"

    # assert_isolate_transport AFTER drive, not before: the rules and
    # operations workers do not start until a request needs them.
    serve_start "$fixture" "$mode" "$port"
    drive "$fixture" "$mode" seed
    assert_isolate_transport
    serve_stop

    # A response that looks right over a write that never reached the file is
    # the mirror image of a16b499, and only a process that did not perform the
    # writes can tell the difference. Same port: the previous server is gone.
    serve_start "$fixture" "$mode" "$port"
    drive "$fixture" "$mode" verify
    assert_isolate_transport
    serve_stop
  done
  echo ""
done

current_fixture="-"
current_mode="-"
echo "e2e layer passed."
