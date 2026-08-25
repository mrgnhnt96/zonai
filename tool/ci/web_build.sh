#!/usr/bin/env bash
# `jaspr build` for apps/web, with the one failure it cannot explain recovered
# from instead of reported.
#
# THE FAILURE. `sip run web gen` runs `server.sync-to-cli` BEFORE this build,
# and that step does `rm -rf apps/zonai/lib/gen/server` followed by a fresh
# `cp -r apps/server`. Every file in that tree is therefore a new file with a
# new identity. apps/web path-depends on `zonai`, so build_runner's cached
# asset graph in apps/web/.dart_tool/build still carries entries for the files
# that were deleted -- and it may not delete an output belonging to a package
# that is not a build root. It aborts with:
#
#   [ERROR] InvalidOutputException: zonai|lib/gen/server/.revali/server/routes/__r3_route.module.library
#   [ERROR] Tried to delete from package not in the build. Packages in the build are: zonai_web
#   ✗ [BUILDER] Failed to build with build_runner/aot in 10s; wrote 0 outputs.
#
# and `sip` then prints "Commands failed / No output or error to show", so the
# reason is two scrollbacks above the thing that reports the failure. Nothing
# stale exists ON DISK -- `find apps/zonai/lib/gen/server -name '*.module*'`
# returns nothing -- so it does not read as a cache problem, and the named path
# points at a generated tree that looks like the real suspect. It cost a
# session most of an hour.
#
# WHY RETRY AND NOT ALWAYS CLEAR. Dropping .dart_tool/build unconditionally
# turns every incremental build into a cold dart2js -- ~50s of compile on a
# tree that usually has nothing to redo. The graph is only ever poisoned by a
# sync-to-cli that ran between two builds, so clearing on the failure and
# retrying once pays that cost exactly when it is owed.
#
# WHY A WRAPPER. `sip run web gen` reaches this, and so does anyone running the
# build by hand -- same reasoning tool/ci/docs_build.sh carries for its own
# unexplainable failure.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root/apps/web" || exit 1

# `mktemp -t <prefix>` is BSD-only: on macOS it appends a random suffix, but GNU
# coreutils reads the argument as a TEMPLATE and refuses one without three X's
# --- "mktemp: too few X's in template". `$log` was then empty, `tee ""` failed,
# and with pipefail that turned a SUCCESSFUL jaspr build into a failed one, on
# every Linux and Windows runner while both macOS legs stayed green. It cost
# Compile 32795339596 (v0.8.4) three of its five platforms. A positional
# template is the portable spelling and works on both.
log="$(mktemp "${TMPDIR:-/tmp}/zonai_web_build.XXXXXX")" || exit 1
trap 'rm -f "$log"' EXIT

dart pub get || exit 1

# First attempt. Tee rather than capture: a build this long must stay visible
# while it runs, and a silent five minutes reads as a hang.
if dart run jaspr_cli:jaspr build 2>&1 | tee "$log"; then
  exit 0
fi

if ! grep -q 'Tried to delete from package not in the build' "$log"; then
  echo >&2
  echo "web build: FAILED, and not with the stale-asset-graph signature this" >&2
  echo "  wrapper knows how to recover from. The build output above is the" >&2
  echo "  whole story; nothing was retried." >&2
  exit 1
fi

echo >&2
echo "web build: STALE BUILD_RUNNER ASSET GRAPH — clearing it and retrying once." >&2
echo >&2
echo "  server.sync-to-cli replaced apps/zonai/lib/gen/server wholesale, so the" >&2
echo "  cached graph in apps/web/.dart_tool/build still names files that no" >&2
echo "  longer exist, in a package it is not allowed to delete from. Nothing is" >&2
echo "  wrong with the source. This is the documented remedy, not a workaround." >&2
echo >&2

rm -rf .dart_tool/build build/jaspr

# build/jaspr is dropped with it deliberately: a half-populated one turns three
# normally-skipped docs tests into failures, so a failed build must not leave
# one behind for the next command to trip over.
exec dart run jaspr_cli:jaspr build
