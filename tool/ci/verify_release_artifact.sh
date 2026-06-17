#!/usr/bin/env bash
set -euo pipefail

executable="${1:?executable path required}"
playground_dir="${2:-apps/playground}"
serve_seconds="${3:-5}"

executable="$(cd "$(dirname "$executable")" && pwd)/$(basename "$executable")"

if [[ ! -x "$executable" ]]; then
  chmod +x "$executable"
fi

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

cd "$playground_dir"

echo "Verifying compile..."
"$executable" compile

echo "Verifying serve (must stay running for ${serve_seconds}s)..."
"$executable" serve --log verbose --no-version-check &
serve_pid=$!

deadline=$(( $(date +%s) + serve_seconds ))
health_ok=false

echo "Waiting for /health..."
while (( $(date +%s) < deadline )); do
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
  echo "health check failed within ${serve_seconds}s" >&2
  exit 1
fi

remaining=$(( deadline - $(date +%s) ))
if (( remaining > 0 )); then
  sleep "$remaining"
fi

if ! kill -0 "$serve_pid" 2>/dev/null; then
  wait "$serve_pid" 2>/dev/null || true
  echo "serve exited before ${serve_seconds}s" >&2
  exit 1
fi

kill "$serve_pid" 2>/dev/null || true
wait "$serve_pid" 2>/dev/null || true
echo "serve stayed running for ${serve_seconds}s"
