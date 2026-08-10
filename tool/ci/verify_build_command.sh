#!/usr/bin/env bash
# Verify `zonai build` still produces a deployable bundle, for the current
# OS/arch, against a project shaped like every real one.
#
# verify_release_artifact.sh drives `compile`/`serve` against apps/playground,
# which carries a `zonai: {path: ...}` dev dependency. That is not what a real
# project looks like -- zonai ships as a standalone binary and is never an
# application dependency -- and it is not the code path `zonai build` takes
# there. Between v0.5 and v0.6 `zonai build` was broken for every project
# without that dependency (it unconditionally compiled a project-linked binary
# whose entry imports `package:zonai/...`, which cannot resolve) and nothing in
# CI noticed, because nothing in CI ran `build`.
#
# So: run the real command against e2e/build_smoke (zonai_schema only), then
# prove the bundle it emits actually serves -- the artifact a deploy copies,
# not just a file that exists.
#
# Usage: verify_build_command.sh <executable> [fixture-dir] [health-timeout-s]
set -euo pipefail

executable="${1:?executable path required}"
fixture_dir="${2:-e2e/build_smoke}"
health_timeout_seconds="${3:-60}"

executable="$(cd "$(dirname "$executable")" && pwd)/$(basename "$executable")"
if [[ ! -x "$executable" ]]; then
  chmod +x "$executable"
fi

# `zonai build` names its output for the *target*, which here is the host.
built_name="zonai"
if [[ "$executable" == *.exe ]]; then
  built_name="zonai.exe"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f "${repo_root}/VERSION" ]]; then
  bash "${repo_root}/tool/ci/sync_playground_version.sh" \
    "${fixture_dir}" "${repo_root}/VERSION"
fi

cd "${repo_root}/${fixture_dir}"

# Start from nothing so a stale bundle can never satisfy the assertions below.
rm -rf build .zonai

echo "Resolving fixture dependencies..."
dart pub get

echo "Generating a migration so the bundle has one to carry..."
"$executable" db migrate generate --name initialize --no-version-check

echo "Running zonai build..."
"$executable" build --no-version-check

echo "Checking bundle contents..."
require_file() {
  if [[ ! -f "$1" ]]; then
    echo "zonai build did not produce $1" >&2
    exit 1
  fi
  echo "  ok: $1"
}

require_file "build/${built_name}"
require_file "build/zonai.yaml"

if ! compgen -G "build/.zonai/migrations/*.sql" >/dev/null; then
  echo "zonai build did not copy migrations into build/.zonai/migrations" >&2
  exit 1
fi
echo "  ok: build/.zonai/migrations/*.sql"

# The bundled binary drives ops/rules over IPC, so a bundle missing these
# starts fine and then fails on the first db call.
#
# Only the two the fixture defines content for are required. Which of the
# optional workers (config, crons, rate limits, extensions) get emitted
# depends on what the project declares -- db_config, for instance, is skipped
# outright when there is no lib/src/config -- and pinning that here would gate
# on generator internals rather than on the bundle being usable.
for worker in db_operations db_rules; do
  if ! compgen -G "build/.zonai/executables/${worker}.exe" >/dev/null; then
    echo "zonai build did not bundle worker ${worker}" >&2
    ls -la build/.zonai/executables 2>/dev/null >&2 || true
    exit 1
  fi
  echo "  ok: build/.zonai/executables/${worker}.exe"
done

# Each worker carries a sidecar recording the IPC wire version it was built
# against; the host refuses a stale pairing only if this is present.
for worker_exe in build/.zonai/executables/*.exe; do
  if [[ ! -f "${worker_exe%.exe}.protocol" ]]; then
    echo "bundled worker ${worker_exe} has no .protocol stamp" >&2
    exit 1
  fi
done
echo "  ok: every bundled worker carries a .protocol stamp"

if [[ ! -x "build/${built_name}" ]]; then
  chmod +x "build/${built_name}"
fi

echo "Checking the bundled binary runs..."
"./build/${built_name}" version --no-version-check --no-schema-version-check

# Everything above proves the bundle was assembled. This proves it works:
# serve out of build/ exactly as a deploy does (see the Dockerfile layout --
# ./zonai beside ./zonai.yaml and ./.zonai), which is also the only check here
# that exercises the native libraries and the host<->worker IPC pairing.
health_urls=(
  "http://127.0.0.1:8080/health"
  "http://[::1]:8080/health"
  "http://localhost:8080/health"
)

check_server_health() {
  local url
  for url in "${health_urls[@]}"; do
    if curl -sf --max-time 2 "$url" >/dev/null; then
      echo "Health check passed: $url"
      return 0
    fi
  done
  return 1
}

cd build

echo "Applying migrations inside the bundle..."
"./${built_name}" db migrate apply --no-version-check

echo "Serving from the bundle (timeout ${health_timeout_seconds}s for /health)..."
"./${built_name}" serve --log verbose --no-version-check &
serve_pid=$!

cleanup() {
  kill "$serve_pid" 2>/dev/null || true
  wait "$serve_pid" 2>/dev/null || true
}
trap cleanup EXIT

deadline=$(( $(date +%s) + health_timeout_seconds ))
health_ok=false
while (( $(date +%s) < deadline )); do
  if ! kill -0 "$serve_pid" 2>/dev/null; then
    wait "$serve_pid" 2>/dev/null || true
    echo "the bundled server exited before answering /health" >&2
    exit 1
  fi

  if check_server_health; then
    health_ok=true
    break
  fi

  sleep 0.5
done

if [[ "$health_ok" != true ]]; then
  echo "the bundled server never answered /health within ${health_timeout_seconds}s" >&2
  exit 1
fi

echo "zonai build produced a bundle that serves."
