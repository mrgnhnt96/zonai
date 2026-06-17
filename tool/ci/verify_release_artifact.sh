#!/usr/bin/env bash
set -euo pipefail

executable="${1:?executable path required}"
playground_dir="${2:-apps/playground}"
serve_seconds="${3:-5}"

executable="$(cd "$(dirname "$executable")" && pwd)/$(basename "$executable")"

if [[ ! -x "$executable" ]]; then
  chmod +x "$executable"
fi

cd "$playground_dir"

echo "Verifying compile..."
"$executable" compile

echo "Verifying serve (must stay running for ${serve_seconds}s)..."
"$executable" serve --log verbose --no-version-check &
serve_pid=$!

sleep "$serve_seconds"

if ! kill -0 "$serve_pid" 2>/dev/null; then
  wait "$serve_pid" 2>/dev/null || true
  echo "serve exited before ${serve_seconds}s" >&2
  exit 1
fi

kill "$serve_pid" 2>/dev/null || true
wait "$serve_pid" 2>/dev/null || true
echo "serve stayed running for ${serve_seconds}s"
