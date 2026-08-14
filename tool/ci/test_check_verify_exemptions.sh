#!/usr/bin/env bash
# Negative controls for check_verify_exemptions.sh.
#
# WHY THIS EXISTS: the thing being added is a check whose whole job is to fail on a schedule. On the
# day it is written it passes, and a checker that has only ever been seen passing is
# indistinguishable from one that cannot fail -- which is the exact defect it was written to stop
# (a `dart analyze` rule standing in for a `dart test` rule, green either way). So each way it is
# supposed to refuse gets provoked here against a deliberately-broken copy of the manifest, and the
# real manifest is asserted to pass.
#
# WHAT IT DOES NOT COVER: whether the TRIGGERS list catches every phrasing a human might use for a
# temporary downgrade. It cannot -- prose matching is a heuristic, and the structural half (a rule
# whose commands are all analyze-only) is the part that does not depend on wording.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

check="tool/ci/check_verify_exemptions.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
pass=0
fail=0

# Provoke one failure mode and assert the checker refuses, naming the reason.
expect_fail() {
  local name="$1" expect="$2" map="$3"
  local out rc
  out="$(VERIFY_MAP="${map}" bash "${check}" 2>&1)"; rc=$?
  if [ "${rc}" -eq 0 ]; then
    echo "  FAIL: ${name} -- checker exited 0; it should have refused"
    fail=$((fail + 1))
  elif ! grep -qF "${expect}" <<<"${out}"; then
    echo "  FAIL: ${name} -- refused, but not for the expected reason (${expect})"
    echo "${out}" | sed 's/^/        /'
    fail=$((fail + 1))
  else
    echo "  ok: ${name}"
    pass=$((pass + 1))
  fi
}

echo "negative controls for ${check}:"

# 1. An analyze-only rule with no marker at all -- the shape all six stale exemptions had.
cat >"${tmp}/no_marker.yaml" <<'EOF'
# Just an import swap, so analyze is enough.
"lib/thing.dart":
  - "dart analyze lib/thing.dart"
EOF
expect_fail "analyze-only rule, no RECHECK marker" "carries no RECHECK marker" "${tmp}/no_marker.yaml"

# 2. A dated marker whose date has passed -- the whole point of the mechanism.
cat >"${tmp}/overdue.yaml" <<'EOF'
# RECHECK 2020-01-01 -- re-run the real thing.
"lib/thing.dart":
  - "dart analyze lib/thing.dart"
  - "bash tool/ci/check_verify_exemptions.sh"
EOF
expect_fail "RECHECK date in the past" "came due" "${tmp}/overdue.yaml"

# 3. A date parked far enough out that it never comes due.
cat >"${tmp}/horizon.yaml" <<'EOF'
# RECHECK 2099-01-01 -- someday.
"lib/thing.dart":
  - "dart analyze lib/thing.dart"
  - "bash tool/ci/check_verify_exemptions.sh"
EOF
expect_fail "RECHECK date past the 180-day cap" "days out" "${tmp}/horizon.yaml"

# 4. A marker with nothing wired to enforce it -- a note, not a check.
cat >"${tmp}/unenrolled.yaml" <<'EOF'
# RECHECK 2099-01-01 -- but nothing runs the checker.
"lib/thing.dart":
  - "dart analyze lib/thing.dart"
EOF
expect_fail "marker present, checker not in the rule's commands" "never runs the check" \
  "${tmp}/unenrolled.yaml"

# 5. A prose justification that is time-bound, on a rule that DOES run a real test. The rule is not
#    structurally exempt, so only the trigger phrase catches it.
cat >"${tmp}/timebound.yaml" <<'EOF'
# The e2e fails locally for pre-existing reasons, so this runs the unit test instead.
"lib/thing.dart":
  - "dart test test/thing_test.dart"
EOF
expect_fail "time-bound prose on a rule with a real check" "time-bound claim" "${tmp}/timebound.yaml"

# 6. A key listed twice. verify.yaml is parsed into a dict, so the earlier rule is silently dropped
#    -- comment, commands and all. Two of these were live in this repo on 2026-08-13.
cat >"${tmp}/dupe.yaml" <<'EOF'
# RECHECK never -- fine.
"lib/thing.dart":
  - "dart test a"
  - "bash tool/ci/check_verify_exemptions.sh"

"lib/thing.dart":
  - "dart test b"
EOF
expect_fail "duplicate top-level key" "DUPLICATE KEY" "${tmp}/dupe.yaml"

# 7. Enrolling a rule must not switch the requirement off for that rule. check_verify_exemptions.sh
#    ends in `.sh`, which the "is there a real check here?" test would otherwise count as one -- so
#    complying would silence the detector. This is the control for that self-defeat.
cat >"${tmp}/self_silence.yaml" <<'EOF'
# No marker, but it does run the checker, which must NOT count as this rule's real check.
"lib/thing.dart":
  - "dart analyze lib/thing.dart"
  - "bash tool/ci/check_verify_exemptions.sh"
EOF
expect_fail "the checker itself does not count as a rule's real check" "carries no RECHECK marker" \
  "${tmp}/self_silence.yaml"

# 8. A path both excluded as unchecked-ok and claimed by a rule. The rule wins, so the exclusion is
#    inert while still reading as a live decision contradicting it. One was live on 2026-08-13.
cat >"${tmp}/overlap.yaml" <<'EOF'
# RECHECK never -- fine.
"lib/thing.dart":
  - "dart test a"
  - "bash tool/ci/check_verify_exemptions.sh"

"unchecked-ok":
  - "lib/thing.dart"
EOF
expect_fail "path both excluded and claimed by a rule" "AND claimed by a rule" "${tmp}/overlap.yaml"

# 9. An unreadable manifest must refuse, not report a clean sweep. Treating "cannot look" as "nothing
#    to see" is the same false green as everything above.
expect_fail "missing manifest" "not a pass" "${tmp}/does_not_exist.yaml"

# And the positive control: the real manifest passes. Without this, every check above would still
# pass if the script simply always exited 1.
echo
if out="$(bash "${check}" 2>&1)"; then
  echo "  ok: the real .game_loop/verify.yaml passes"
  echo "${out}" | sed 's/^/        /'
  pass=$((pass + 1))
else
  echo "  FAIL: the real .game_loop/verify.yaml does not pass"
  echo "${out}" | sed 's/^/        /'
  fail=$((fail + 1))
fi

echo
echo "${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
