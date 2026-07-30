#!/usr/bin/env bash
# Simulate a user upgrading zonai: set up a project with the old binary, then
# verify the new binary still compiles, applies migrations on the existing DB,
# serves, and does not regenerate SQL for unchanged app schemas.
#
# Usage: verify_compat.sh <old_binary_path> <new_binary_path>
set -euo pipefail

old_binary="${1:?old binary path required}"
new_binary="${2:?new binary path required}"

serve_seconds="${SERVE_SECONDS:-5}"
health_timeout_seconds="${HEALTH_TIMEOUT_SECONDS:-30}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
compat_dir="${repo_root}/apps/compat"
compat_db_path="${compat_dir}/.zonai/data/zonai.sqlite"

old_binary="$(cd "$(dirname "$old_binary")" && pwd)/$(basename "$old_binary")"
new_binary="$(cd "$(dirname "$new_binary")" && pwd)/$(basename "$new_binary")"

health_urls=(
  "http://127.0.0.1:8080/health"
  "http://[::1]:8080/health"
  "http://localhost:8080/health"
)

ensure_executable() {
  local executable="$1"
  if [[ ! -x "$executable" ]]; then
    chmod +x "$executable"
  fi
}

extract_version() {
  local executable="$1"
  local version

  # Run outside the compat project so placeholder zonai.yaml cannot interfere.
  version="$((cd /tmp && "$executable" version 2>&1) | sed -n 's/^Zonai: v\([0-9][0-9.]*\).*$/\1/p')"
  if [[ -z "$version" ]]; then
    echo "Failed to extract version from: $executable" >&2
    "$executable" version >&2 || true
    exit 1
  fi

  echo "$version"
}

set_zonai_version() {
  local version="$1"
  perl -pi -e "s/^version: .*/version: ${version}/" "${compat_dir}/zonai.yaml"
  echo "Set ${compat_dir}/zonai.yaml version to ${version}"
}

reset_compat_state() {
  rm -rf "${compat_dir}/.zonai" "${compat_dir}/.dart_tool"
}

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

verify_serve() {
  local executable="$1"
  echo "Verifying serve (must respond on /health, then stay up for ${serve_seconds}s)..."

  "$executable" serve --log verbose --no-version-check &
  local serve_pid=$!

  local health_deadline=$(( $(date +%s) + health_timeout_seconds ))
  local health_ok=false

  echo "Waiting for /health (timeout ${health_timeout_seconds}s)..."
  while (( $(date +%s) < health_deadline )); do
    if ! kill -0 "$serve_pid" 2>/dev/null; then
      wait "$serve_pid" 2>/dev/null || true
      echo "serve exited before health check" >&2
      exit 1
    fi

    if check_server_health; then
      health_ok=true
      break
    fi

    sleep 0.5
  done

  if [[ "$health_ok" != true ]]; then
    kill "$serve_pid" 2>/dev/null || true
    wait "$serve_pid" 2>/dev/null || true
    echo "health check failed within ${health_timeout_seconds}s" >&2
    exit 1
  fi

  sleep "$serve_seconds"

  if ! kill -0 "$serve_pid" 2>/dev/null; then
    wait "$serve_pid" 2>/dev/null || true
    echo "serve exited before ${serve_seconds}s after health check" >&2
    exit 1
  fi

  kill "$serve_pid" 2>/dev/null || true
  wait "$serve_pid" 2>/dev/null || true
  echo "serve stayed running for ${serve_seconds}s after health check"
}

assert_migrations_exist() {
  local count
  count="$(find "${compat_dir}/.zonai/migrations" -maxdepth 1 -name '*.sql' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" -lt 1 ]]; then
    echo "Expected migration SQL files under ${compat_dir}/.zonai/migrations" >&2
    exit 1
  fi
  echo "Found ${count} migration SQL file(s)"
}

assert_db_exists() {
  if [[ ! -f "$compat_db_path" ]]; then
    echo "Expected database at ${compat_db_path}" >&2
    exit 1
  fi
  echo "Database present: ${compat_db_path}"
}

assert_no_schema_changes() {
  local executable="$1"
  local output

  echo "Verifying migration snapshots (dry-run)..."
  if ! output="$("$executable" db migrate generate --name compat-check --dry-run --no-version-check 2>&1)"; then
    echo "$output" >&2
    exit 1
  fi

  if ! grep -Fq 'No changes detected' <<< "$output"; then
    echo "New binary would regenerate migrations from old snapshots:" >&2
    echo "$output" >&2
    exit 1
  fi

  echo "Migration snapshots unchanged (no schema diff)"
}

ensure_executable "$old_binary"
ensure_executable "$new_binary"

echo "=== Phase 1: Create project state with old binary ==="
old_version="$(extract_version "$old_binary")"
echo "Old binary version: ${old_version}"

reset_compat_state
set_zonai_version "$old_version"

echo "Running dart pub get..."
(
  cd "${repo_root}"
  dart pub get
)

(
  cd "${compat_dir}"
  echo "Old binary: compile"
  "$old_binary" compile --no-version-check

  echo "Old binary: generate initial migration"
  "$old_binary" db migrate generate --name initialize --no-version-check

  echo "Old binary: apply migrations (internal + user)"
  "$old_binary" db migrate apply --no-version-check

  echo "Old binary: serve on migrated database"
  verify_serve "$old_binary"
)

assert_migrations_exist
assert_db_exists

echo "=== Phase 2: Simulate user upgrade (update zonai.yaml version only) ==="
new_version="$(extract_version "$new_binary")"
echo "New binary version: ${new_version}"
set_zonai_version "$new_version"

echo "=== Phase 3: Verify new binary against old project state ==="
(
  cd "${compat_dir}"

  echo "New binary: compile"
  "$new_binary" compile

  echo "New binary: apply pending migrations on database from old release"
  "$new_binary" db migrate apply --no-version-check
  assert_db_exists

  echo "New binary: serve on upgraded database"
  verify_serve "$new_binary"

  assert_no_schema_changes "$new_binary"
)

echo "Compatibility check passed (old v${old_version} -> new v${new_version})"
