#!/usr/bin/env bash
# Controls for vm_snapshot_defines.sh, the script that decides what runtime
# identity every released zonai binary claims.
#
# It is worth its own harness because two of its failure modes are silent. A
# wrong hash bakes a lie the guard then believes -- worse than baking nothing.
# And "found the hash" and "found a 32-character window inside a 200-byte slab
# of '4's" are the same observation to a naive grep: measured against the 3.12.0
# `dartaotruntime`, `grep -o '[0-9a-f]\{32\}'` returns SEVEN distinct values and
# the maximal-run spelling returns exactly one. Case "long hex run" below is
# that regression, and without it "we still find one hash" and "we stopped
# looking properly" read identically.
#
# The synthetic cases drive the real script against fabricated SDK trees; the
# last case drives it against whichever Dart SDK is actually on PATH, because a
# harness that only ever sees files it wrote itself proves nothing about the
# layout it has to survive.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UNDER_TEST="${ROOT}/tool/ci/vm_snapshot_defines.sh"

work="$(mktemp -d "${TMPDIR:-/tmp}/zonai_vm_defines.XXXXXX")"
trap 'rm -rf "$work"' EXIT

HASH_A=41be3daaabd524b8aa7423bc24584957
HASH_B=0451907c2eaa8467e848c0067bfe8ed4

# $1 sdk dir, $2 version file contents ('-' for none), rest: byte runs to write
# into the fake dartaotruntime, each surrounded by non-hex bytes so it reads as
# a maximal run.
make_sdk() {
  local dir="$1" version="$2"
  shift 2
  mkdir -p "$dir/bin"
  # A `dart` that answers --version, so the fallback path has something real to
  # parse when the version file is absent.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "Dart SDK version: 9.9.9 (stable) (Mon Jan 1 00:00:00 2026 +0000) on \\"test\\""\n'
  } > "$dir/bin/dart"
  chmod +x "$dir/bin/dart"

  : > "$dir/bin/dartaotruntime"
  local run
  for run in "$@"; do
    printf '\000\001ZZ%sZZ\000\n' "$run" >> "$dir/bin/dartaotruntime"
  done

  if [ "$version" != "-" ]; then
    printf '%s\n' "$version" > "$dir/version"
  fi
}

# $1 label, $2 dart path, $3 expected exit, $4 grep over combined output
run_case() {
  local label="$1" dart="$2" want_exit="$3" want_text="$4"
  local log="$work/out.txt" got=0
  bash "$UNDER_TEST" "$dart" > "$log" 2>&1 || got=$?

  if [ "$got" != "$want_exit" ]; then
    echo "FAIL  ${label}: exit ${got}, wanted ${want_exit}" >&2
    sed 's/^/      /' "$log" >&2
    return 1
  fi
  if [ "$want_text" != "-" ] && ! grep -q -- "$want_text" "$log"; then
    echo "FAIL  ${label}: output did not contain '${want_text}'" >&2
    sed 's/^/      /' "$log" >&2
    return 1
  fi
  echo "ok    ${label}"
}

failed=0

make_sdk "$work/plain" 3.12.0 "$HASH_A"
run_case "one hash and a version file -> both defines" \
  "$work/plain/bin/dart" 0 "--define=ZONAI_VM_HASH=${HASH_A}" || failed=1
run_case "  ...and the version comes from <sdk>/version" \
  "$work/plain/bin/dart" 0 "--define=ZONAI_DART_SDK=3.12.0" || failed=1

# THE REGRESSION. A 40-character run is not a hash, and a scanner that reports
# 32-character windows sees a second value here and refuses.
make_sdk "$work/longrun" 3.12.0 "$HASH_A" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
run_case "a longer hex run is not a hash, and does not make the file ambiguous" \
  "$work/longrun/bin/dart" 0 "--define=ZONAI_VM_HASH=${HASH_A}" || failed=1

# 31 and 33 are near misses on the other side.
make_sdk "$work/nearmiss" 3.12.0 "$HASH_A" "0123456789abcdef0123456789abcde" \
  "0123456789abcdef0123456789abcdef0"
run_case "31 and 33 character runs are ignored" \
  "$work/nearmiss/bin/dart" 0 "--define=ZONAI_VM_HASH=${HASH_A}" || failed=1

# Uppercase must not count, for the same reason the Dart side excludes it.
make_sdk "$work/upper" 3.12.0 "$HASH_A" "0123456789ABCDEF0123456789ABCDEF"
run_case "an uppercase 32-run is not a candidate" \
  "$work/upper/bin/dart" 0 "--define=ZONAI_VM_HASH=${HASH_A}" || failed=1

# The same value twice is still one answer.
make_sdk "$work/repeat" 3.12.0 "$HASH_A" "$HASH_A" "$HASH_A"
run_case "the same hash several times is one answer" \
  "$work/repeat/bin/dart" 0 "--define=ZONAI_VM_HASH=${HASH_A}" || failed=1

# Two different values are not.
make_sdk "$work/ambiguous" 3.12.0 "$HASH_A" "$HASH_B"
run_case "two different hashes -> refuse, loudly" \
  "$work/ambiguous/bin/dart" 1 "found 2" || failed=1

make_sdk "$work/empty" 3.12.0
run_case "no hash at all -> refuse rather than bake an empty define" \
  "$work/empty/bin/dart" 1 "found 0" || failed=1

# A `dart` with no runtime beside it cannot answer, and must say which path it
# looked at rather than shipping an unguarded binary.
mkdir -p "$work/noruntime/bin"
: > "$work/noruntime/bin/dart"
chmod +x "$work/noruntime/bin/dart"
run_case "no dartaotruntime beside dart -> refuse" \
  "$work/noruntime/bin/dart" 1 "no dartaotruntime" || failed=1

# The shape every SDK manager installs: a name pointing into a versioned SDK.
make_sdk "$work/versioned" 3.12.0 "$HASH_A"
mkdir -p "$work/shims"
ln -sf "$work/versioned/bin/dart" "$work/shims/dart"
run_case "a symlinked dart resolves to its SDK" \
  "$work/shims/dart" 0 "--define=ZONAI_VM_HASH=${HASH_A}" || failed=1

# Version is best-effort: losing it costs message text, not the guard.
make_sdk "$work/noversion" -
printf '\000ZZ%sZZ\000\n' "$HASH_A" > "$work/noversion/bin/dartaotruntime"
run_case "no <sdk>/version -> falls back to dart --version" \
  "$work/noversion/bin/dart" 0 "--define=ZONAI_DART_SDK=9.9.9" || failed=1

make_sdk "$work/noversionatall" -
printf '\000ZZ%sZZ\000\n' "$HASH_A" > "$work/noversionatall/bin/dartaotruntime"
printf '#!/usr/bin/env bash\nexit 1\n' > "$work/noversionatall/bin/dart"
chmod +x "$work/noversionatall/bin/dart"
run_case "no version anywhere -> still bakes the hash, and says what was lost" \
  "$work/noversionatall/bin/dart" 0 "--define=ZONAI_VM_HASH=${HASH_A}" || failed=1

# Against a real SDK. `dart` is on PATH wherever this runs -- `static` is a Dart
# check target -- so this is not conditional.
real="$work/real.txt"
if bash "$UNDER_TEST" dart > "$real" 2>&1; then
  real_hash="$(sed -n 's/^--define=ZONAI_VM_HASH=//p' "$real")"
  real_version="$(sed -n 's/^--define=ZONAI_DART_SDK=//p' "$real")"
  want_version="$(dart --version 2>&1 | sed -n 's/^Dart SDK version: \([^ ]*\).*/\1/p')"

  if printf '%s' "$real_hash" | grep -qx '[0-9a-f]\{32\}'; then
    echo "ok    the Dart SDK on PATH yields one 32-hex hash (${real_hash})"
  else
    echo "FAIL  the Dart SDK on PATH yielded '${real_hash}', not a 32-hex hash" >&2
    failed=1
  fi

  if [ "$real_version" = "$want_version" ]; then
    echo "ok    the baked version agrees with \`dart --version\` (${real_version})"
  else
    echo "FAIL  baked version '${real_version}' != dart --version '${want_version}'" >&2
    failed=1
  fi
else
  echo "FAIL  the script could not read the Dart SDK on PATH:" >&2
  sed 's/^/      /' "$real" >&2
  failed=1
fi

if [ "$failed" != "0" ]; then
  echo "" >&2
  echo "vm_snapshot_defines.sh's controls did not hold. A released binary would" >&2
  echo "either carry no runtime identity or carry the wrong one." >&2
  exit 1
fi
echo "  ok: vm_snapshot_defines.sh finds exactly the hash, or refuses"
