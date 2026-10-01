#!/usr/bin/env bash
# `sip run test cli` -- apps/zonai's own suite, whole or one shard of it.
#
# With ZONAI_TEST_SHARD unset this is exactly `dart test` in apps/zonai, which
# is what a contributor runs. CI sets it to `<index>/<total>` (1-based) so the
# suite can be spread over several runners: on a 4-vCPU runner `dart test`
# runs only two suites at a time, and the 29 compiled-project e2e suites alone
# took ~13 of the windows leg's ~18 minutes (run 36809321033).
#
# SHARDED BY FILE, NOT WITH `dart test --total-shards`. package:test shards by
# test case, so every shard would still load every suite and run its
# setUpAll -- and in the e2e suites setUpAll is the cost (copy a fixture, pub
# get, `zonai compile`, migrate generate/apply), not the tests after it.
#
# Files are dealt round-robin from a sorted list. The slow suites sit together
# in test/e2e/, so dealing them one at a time spreads them evenly without a
# hand-kept list of which file is heavy -- a list like that goes stale the
# first time a fixture is added. Every file lands in exactly one shard, and a
# new test file is picked up without touching this script or the workflow.
set -euo pipefail

cd "$(dirname "$0")/../../apps/zonai"

if [ -z "${ZONAI_TEST_SHARD:-}" ]; then
  exec dart test "$@"
fi

case "${ZONAI_TEST_SHARD}" in
  */*) ;;
  *)
    echo "ZONAI_TEST_SHARD must be <index>/<total>, got '${ZONAI_TEST_SHARD}'" >&2
    exit 64
    ;;
esac
index="${ZONAI_TEST_SHARD%/*}"
total="${ZONAI_TEST_SHARD#*/}"
if ! [ "${index}" -ge 1 ] 2>/dev/null || ! [ "${total}" -ge "${index}" ] 2>/dev/null; then
  echo "ZONAI_TEST_SHARD must be <index>/<total> with 1 <= index <= total, got '${ZONAI_TEST_SHARD}'" >&2
  exit 64
fi

all=()
while IFS= read -r file; do
  all+=("${file}")
done < <(find test -name '*_test.dart' -type f | LC_ALL=C sort)

if [ "${#all[@]}" -eq 0 ]; then
  echo "no *_test.dart files under apps/zonai/test" >&2
  exit 1
fi

mine=()
for i in "${!all[@]}"; do
  if [ $(( i % total + 1 )) -eq "${index}" ]; then
    mine+=("${all[$i]}")
  fi
done

echo "shard ${index}/${total}: ${#mine[@]} of ${#all[@]} test files"
if [ "${#mine[@]}" -eq 0 ]; then
  # More shards than files. Nothing to run is not a pass worth reporting as
  # one, but it is not this shard's failure either.
  echo "nothing to run in this shard"
  exit 0
fi

exec dart test "$@" "${mine[@]}"
