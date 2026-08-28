#!/usr/bin/env bash
# Prints the `--define`s that stamp a zonai host binary with the runtime
# identity of the SDK compiling it, one per line:
#
#   --define=ZONAI_VM_HASH=<32-hex VM snapshot hash>
#   --define=ZONAI_DART_SDK=<e.g. 3.12.0>
#
# Usage: vm_snapshot_defines.sh [<dart executable>]   (default: `dart`)
#
# WHY A BINARY HAS TO CARRY THIS. A zonai host and the `.aot` worker snapshots
# it loads through `Isolate.spawnUri` must come from Dart SDKs that share a VM
# snapshot hash. Where the container format also changed -- a 3.12.x host
# loading a 3.13.x snapshot -- the mismatch is not an exception the host can
# catch: the process takes SIGABRT (exit 134) inside snapshot_utils.cc before
# any Dart code runs. Deciding BEFORE the spawn is the only thing that survives
# it, and a compiled host has no `dartaotruntime` beside it to read, so the
# answer has to be baked in at compile time. apps/zonai/lib/src/domain/
# vm_snapshot_hash.dart is the other end: it reads these back through
# `String.fromEnvironment`.
#
# WHY IT IS DERIVED HERE RATHER THAN WRITTEN DOWN. CI pins `sdk: "3.12.0"` in
# 18 workflow job definitions. A literal hash next to those would be correct
# until the day one of them is bumped, and then silently wrong -- the binary
# would claim a runtime it does not have, which is worse than claiming nothing,
# because the guard would trust it. Reading the SDK that is actually on PATH
# cannot desync from the SDK that is actually compiling.
#
# WHY IT FAILS INSTEAD OF DEGRADING. An unstamped binary is a supported state
# (`hostVmSnapshotHash` returns null and callers treat that as UNKNOWN), but it
# is not one to arrive at by accident on the release path. Zero matches or two
# different ones means this script no longer understands the SDK layout, and
# baking an empty define would ship that as a silent loss of the guard. The
# VERSION is best-effort by contrast, and deliberately so: it is message text
# only ("requires Dart 3.12.0, you are on 3.13.2") and is never compared, so
# losing it costs a nicer error message and nothing else.
set -euo pipefail

dart_arg="${1:-dart}"

# Maximal runs of lowercase ASCII hex that are exactly 32 characters long, one
# per line, deduplicated.
#
# `tr -c` turns every byte that is not lowercase hex into a newline, so each
# resulting line IS a maximal run and `grep -x` can ask about its whole length.
# That is not the same question as `grep -o '[0-9a-f]\{32\}'`, which happily
# reports 32-character WINDOWS inside longer runs: measured against the 3.12.0
# `dartaotruntime`, the windowed spelling returns seven distinct values (six of
# them slabs of repeated '4's and '5's from zero-fill regions) and the maximal
# one returns exactly the hash. Getting this wrong does not fail loudly -- it
# fails the "more than one" check below and takes the release with it.
#
# Uppercase is excluded on purpose, matching vm_snapshot_hash.dart: the VM
# writes the hash lowercase, and accepting uppercase only widens the set of
# unrelated strings that can collide with it. These two definitions of "a hash"
# must agree -- the one baked in here is compared against the one the CLI reads
# out of an SDK at runtime, so a divergence would read as a mismatch between
# SDKs that are in fact identical.
hex_runs() {
  LC_ALL=C tr -c '0-9a-f' '\n' < "$1" \
    | LC_ALL=C grep -x '[0-9a-f]\{32\}' \
    | LC_ALL=C sort -u
}

# `dart`, then whatever it is a symlink to. The common SDK managers install
# exactly that shape -- a name on PATH pointing into a versioned SDK directory
# -- while `dart-lang/setup-dart` lays down real files, so both have to work.
# The literal sibling is preferred when it exists, since that is the runtime an
# invocation of THIS `dart` would reach for.
#
# `readlink -f` is not used: it does not exist on BSD/macOS, where every dev
# machine here is. The loop below is the portable spelling and is bounded, so a
# symlink cycle ends rather than hanging a release build.
dart_candidates() {
  local path="$1" target hops=0
  case "${path}" in
    */*) ;;
    *) path="$(command -v "${path}" 2>/dev/null || true)" ;;
  esac
  [ -n "${path}" ] || return 0

  printf '%s\n' "${path}"
  while [ -L "${path}" ] && [ "${hops}" -lt 16 ]; do
    target="$(readlink "${path}")"
    case "${target}" in
      /*) path="${target}" ;;
      *) path="$(dirname "${path}")/${target}" ;;
    esac
    printf '%s\n' "${path}"
    hops=$((hops + 1))
  done
}

# The `dartaotruntime` beside the first candidate that has one.
runtime=""
sdk_root=""
while IFS= read -r candidate; do
  [ -n "${candidate}" ] || continue
  case "$(printf '%s' "${candidate}" | LC_ALL=C tr '[:upper:]' '[:lower:]')" in
    *.exe) name="dartaotruntime.exe" ;;
    *) name="dartaotruntime" ;;
  esac
  bin_dir="$(dirname "${candidate}")"
  if [ -f "${bin_dir}/${name}" ]; then
    runtime="${bin_dir}/${name}"
    sdk_root="$(dirname "${bin_dir}")"
    break
  fi
done <<EOF
$(dart_candidates "${dart_arg}")
EOF

if [ -z "${runtime}" ]; then
  echo "vm_snapshot_defines: no dartaotruntime beside '${dart_arg}' (or any" >&2
  echo "  symlink it resolves to). Nothing can read the VM snapshot hash of" >&2
  echo "  this SDK, so the binary would ship unguarded. Point PATH at a real" >&2
  echo "  Dart SDK, or pass its bin/dart as the first argument." >&2
  exit 1
fi

matches="$(hex_runs "${runtime}" || true)"
count="$(printf '%s' "${matches}" | LC_ALL=C grep -c . || true)"

if [ "${count}" != "1" ]; then
  echo "vm_snapshot_defines: expected exactly one 32-hex VM snapshot hash in" >&2
  echo "  ${runtime}, found ${count}." >&2
  [ -z "${matches}" ] || printf '    %s\n' ${matches} >&2
  echo "  Refusing to bake an empty or guessed define: a host that claims the" >&2
  echo "  wrong runtime is worse than one that claims none, because the guard" >&2
  echo "  believes it. Check whether the SDK layout changed." >&2
  exit 1
fi

printf -- '--define=ZONAI_VM_HASH=%s\n' "${matches}"

# Best-effort, and the fallback is not redundant: `<sdk>/version` is a one-line
# file the official SDK archive ships (confirmed for a dart-lang archive and a
# dvm install), but a repackaged or trimmed SDK may not carry it, and `dart
# --version` writes to stdout on some versions and stderr on others.
version=""
if [ -f "${sdk_root}/version" ]; then
  version="$(LC_ALL=C tr -d '[:space:]' < "${sdk_root}/version")"
fi
if [ -z "${version}" ]; then
  # `|| true` because `set -o pipefail` is on and this fallback is reached
  # exactly when the SDK is unusual -- a `dart` that fails to run must leave
  # the version empty and take the warning path below, not kill a build over
  # message text.
  version="$("${dart_arg}" --version 2>&1 \
    | LC_ALL=C sed -n 's/^Dart SDK version: \([^ ]*\).*/\1/p' \
    | head -n 1)" || true
fi

if [ -z "${version}" ]; then
  echo "vm_snapshot_defines: could not read a version for ${sdk_root} --" >&2
  echo "  baking the hash without it. A mismatch will print two hex strings" >&2
  echo "  instead of naming the SDK; nothing else is affected, because the" >&2
  echo "  version is never compared." >&2
else
  printf -- '--define=ZONAI_DART_SDK=%s\n' "${version}"
fi
