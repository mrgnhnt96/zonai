#!/usr/bin/env bash
# `jaspr build` with the one failure it cannot explain named before it happens.
#
# THE FAILURE. jaspr's static generator starts its own server to render routes
# from, and binds 8080 unconditionally -- there is no --port flag and PORT= is
# ignored. When anything else already holds 127.0.0.1:8080 (a long-lived
# `zonai serve` is the usual culprit; one sat there for four days), the
# generator's own requests reach THAT process, which answers 404 for a docs
# route it has never heard of. jaspr reports:
#
#   [ERROR] Failed to generate route "/". (Received status code 404)
#
# Nothing in that says "port conflict", and the obvious reading -- that the
# docs content is broken -- is wrong. It cost a session an hour and a
# --no-verify commit before `lsof` was tried.
#
# WHY A PREFLIGHT AND NOT A FIX. Binding another port belongs upstream in
# jaspr_cli; this repo cannot choose it. What this CAN do is refuse early and
# say which pid to look at, which is the whole difference between a two-minute
# diagnosis and an hour of reading content diffs.
#
# WHY HERE AND NOT IN THE WORKFLOW. `sip run test docs` reaches this from a
# laptop and from CI, and the .game_loop rule for `apps/docs/lib/**` reaches it
# too. One wrapper means all three see the same behaviour -- the same reasoning
# tool/ci/revali_generate.sh carries.
set -uo pipefail

if holder="$(lsof -nP -iTCP:8080 -sTCP:LISTEN -t 2>/dev/null)" && [ -n "$holder" ]; then
  echo "docs build: PORT 8080 IS ALREADY IN USE — this build cannot succeed." >&2
  echo >&2
  echo "  jaspr's static generator binds 8080 unconditionally to render routes from." >&2
  echo "  Whatever is listening will answer its requests instead, and every route" >&2
  echo "  will fail with a 404 that reads like broken content." >&2
  echo >&2
  echo "  Holding it:" >&2
  # shellcheck disable=SC2086 # word splitting is what we want: lsof -t may list several
  ps -o pid=,lstart=,command= -p $holder 2>/dev/null | cut -c1-160 | sed 's/^/    /' >&2
  echo >&2
  echo "  Free that port and re-run. It is not yours to kill without asking if you" >&2
  echo "  did not start it — this checkout is shared with other sessions." >&2
  exit 1
fi

cd apps/docs || exit 1
dart pub get || exit 1
exec dart run jaspr_cli:jaspr build
