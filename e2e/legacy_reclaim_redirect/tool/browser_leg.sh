#!/usr/bin/env bash
# The browser leg of the observation, as one command.
#
# Wraps `bin/probe.dart --serve` because the harness must run through
# showrunner's `device` lock, and that verb's argument parser swallows leading
# `--flags` in the command it is given -- a script takes none.
#
#   showrunner lock run --holder <crawler> device \
#     bash e2e/legacy_reclaim_redirect/tool/browser_leg.sh <code> [browser]
#
# Defaults to the Chrome for Testing binary in the Playwright cache, which is
# what was on this machine; pass a path to use a different browser. Set
# HEADFUL=1 to watch it run in a window.
set -euo pipefail

code="${1:-302}"
browser="${2:-/Users/mrgnhnt96/Library/Caches/ms-playwright/chromium-1234/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"

cd "$(dirname "$0")/.."

args=(run bin/probe.dart --code "$code" --serve --browser "$browser")
if [ "${HEADFUL:-0}" != "1" ]; then
  args+=(--headless)
fi

exec dart "${args[@]}"
