#!/usr/bin/env bash
set -euo pipefail

executable="${1:?executable path required}"
playground_dir="${2:-apps/playground}"
serve_seconds="${3:-5}"
health_timeout_seconds="${4:-30}"

executable="$(cd "$(dirname "$executable")" && pwd)/$(basename "$executable")"

if [[ ! -x "$executable" ]]; then
  chmod +x "$executable"
fi

health_urls=(
  "http://127.0.0.1:8080/health"
  "http://[::1]:8080/health"
  "http://localhost:8080/health"
)

admin_urls=(
  "http://127.0.0.1:8080/auth/admin"
  "http://[::1]:8080/auth/admin"
  "http://localhost:8080/auth/admin"
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

# A passing /health check only proves the HTTP server is up -- it says
# nothing about whether SQLite (resqlite) and Argon2 password hashing
# actually work together end to end. A broken native-library interaction on
# some platform could still pass every check above this one. Create a real
# admin account (exercises Argon2 hashing + a real SQLite write) and sign in
# as that admin over HTTP (exercises Argon2 verification + a real SQLite
# read), failing loudly if either step doesn't work.
check_admin_login() {
  local email="$1"
  local password="$2"
  local url body http_status response

  for url in "${admin_urls[@]}"; do
    response="$(curl -sS --max-time 5 -w '\n%{http_code}' -X POST "$url" \
      -H 'Content-Type: application/json' \
      -d "{\"type\":\"adminSignIn\",\"email\":\"${email}\",\"password\":\"${password}\"}" \
      2>/dev/null)" || continue

    http_status="${response##*$'\n'}"
    body="${response%$'\n'*}"

    if [[ "$http_status" != "200" ]]; then
      echo "Admin sign-in failed at ${url} (HTTP ${http_status}): ${body}" >&2
      return 1
    fi

    if [[ "$body" != *"accessToken"* ]]; then
      echo "Admin sign-in at ${url} returned 200 but no accessToken: ${body}" >&2
      return 1
    fi

    echo "Admin sign-in passed: ${url}"
    return 0
  done

  echo "Could not reach any admin sign-in URL: ${admin_urls[*]}" >&2
  return 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f "${repo_root}/VERSION" ]]; then
  bash "${repo_root}/tool/ci/sync_playground_version.sh" "${playground_dir}" "${repo_root}/VERSION"
fi

cd "${repo_root}/${playground_dir}"

echo "Verifying compile..."
"$executable" compile

# Unique per run so re-running this script locally against a playground
# checkout with a persisted .zonai/data doesn't collide with a
# previously-created admin account.
admin_email="verify-release-admin+$(date +%s)@example.com"
admin_password="verify-release-$$-secret"

# --data supplies the "name" field the playground fixture's admin table
# requires (see apps/playground/lib/src/schemas/users.dart); adjust here if
# this script is ever pointed at a differently-shaped project directory.
echo "Creating admin account (exercises Argon2 hashing + a real SQLite write)..."
"$executable" db admin add \
  --email "$admin_email" \
  --password "$admin_password" \
  --data '{"name":"Verify Release Admin"}' \
  --no-version-check

echo "Verifying serve (must respond on /health, then stay up for ${serve_seconds}s)..."
"$executable" serve --log verbose --no-version-check &
serve_pid=$!

health_deadline=$(( $(date +%s) + health_timeout_seconds ))
health_ok=false

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

echo "Verifying admin sign-in (real Argon2 verify + SQLite read over HTTP)..."
if ! check_admin_login "$admin_email" "$admin_password"; then
  kill "$serve_pid" 2>/dev/null || true
  wait "$serve_pid" 2>/dev/null || true
  echo "admin sign-in check failed" >&2
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
