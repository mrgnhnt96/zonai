#!/usr/bin/env bash
# Run a bundle built on another platform (see cross_target_build.sh) on a
# machine of the platform it was built for.
#
# Four things are checked, and they fail for different reasons:
#
#   1. The bundle runs. Migrations apply, which means resqlite was dlopen'd --
#      the check that would have caught a bundle carrying the build host's
#      libraries.
#   2. The ops/rules .aot snapshots spawn as isolates here. The build half reads
#      their headers; this reads what the VM does with them, which is the thing
#      that actually has to work. Both transports serve identically, so the
#      assertion is the absence of the fallback warning -- and an absence is
#      worth nothing without a case where it appears, hence the control that
#      breaks a snapshot on purpose and requires the warning.
#   3. No library in `.zonai/lib/` is a foreign object file afterwards, and any
#      that shipped with the bundle is byte-identical. Every executable here
#      extracts to that *same* path, so one of them getting it wrong replaces
#      the library for all of them; reading the headers after the run is how
#      that shows up as a failure rather than as the next deployment's mystery.
#      The header check works whether or not the bundle carried libraries,
#      which matters because a pre-release bundle cannot carry them.
#   4. A cross-compiled binary refuses to install its own embedded libraries
#      here (negative control), and still keeps a correctly stamped one
#      (positive control). Without the negative control this gate would pass
#      just as happily against a build that writes the wrong library, because
#      nothing else here forces the self-extraction path to run.
#
# A missing probe (passed as `-`, or a path that does not exist) skips 4 and
# says so. cross_target_build.sh only builds one where the embedded-library
# sources are present.
#
# Usage: verify_cross_target_bundle.sh <bundle-dir> <probe> [version-file]
set -euo pipefail

bundle_dir="${1:?bundle directory required}"
probe="${2:?probe path required}"
version_file="${3:-}"

# shellcheck source=tool/ci/object_platform.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/object_platform.sh"

bundle_dir="$(cd "$bundle_dir" && pwd)"
if [[ "$probe" == "-" || ! -f "$probe" ]]; then
  probe=""
else
  probe="$(cd "$(dirname "$probe")" && pwd)/$(basename "$probe")"
fi

target_os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$target_os" in
  darwin) target_os=macos; library_suffix=.dylib ;;
  linux) library_suffix=.so ;;
  *) echo "Unsupported runner platform: ${target_os}" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) target_arch=x64 ;;
  arm64|aarch64) target_arch=arm64 ;;
  *) echo "Unsupported runner architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [[ -n "$version_file" ]]; then
  version="$(tr -d '[:space:]' < "$version_file")"
else
  version="$(tr -d '[:space:]' < "$(dirname "${BASH_SOURCE[0]}")/../../VERSION")"
fi

resqlite_library="libresqlite${library_suffix}"
argon2_library="libargon2sodium${library_suffix}"

# A bundle that arrived without its payload is not a failing check, it is a
# broken handoff, and the two must not read the same. Everything below lives
# under `.zonai/`, which actions/upload-artifact drops unless the upload sets
# include-hidden-files -- so this is the shape that mistake takes, and it is
# worth naming rather than surfacing as `find: no such file`.
for required in "${bundle_dir}/zonai" "${bundle_dir}/.zonai/executables"; do
  if [[ ! -e "$required" ]]; then
    echo "The bundle is missing ${required}." >&2
    echo "Nothing here was checked. If this came from an artifact, confirm the" >&2
    echo "upload set include-hidden-files: true -- the whole payload is under" >&2
    echo "a dot-directory and is dropped silently without it." >&2
    ls -la "$bundle_dir" >&2 || true
    exit 1
  fi
done

# Artifact upload does not preserve the executable bit.
if [[ -n "$probe" ]]; then
  chmod +x "$probe"
fi
chmod +x "${bundle_dir}/zonai"
find "${bundle_dir}/.zonai/executables" -name '*.exe' -exec chmod +x {} +

digest_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

cd "$bundle_dir"

echo "== 1. the bundle runs on ${target_os}/${target_arch} =="
# Digests only for what actually shipped: a pre-release bundle has no
# .zonai/lib at all, and the run is still worth making.
before_resqlite=""
before_argon2=""
if [[ -f ".zonai/lib/${resqlite_library}" ]]; then
  before_resqlite="$(digest_of ".zonai/lib/${resqlite_library}")"
fi
if [[ -f ".zonai/lib/${argon2_library}" ]]; then
  before_argon2="$(digest_of ".zonai/lib/${argon2_library}")"
fi

./zonai version --no-version-check --no-schema-version-check
./zonai db migrate apply --no-version-check

# Applying a migration means the database opened, which means the library
# loaded. Asserting the file exists is what distinguishes that from a command
# that printed success without touching anything.
if ! compgen -G ".zonai/data/*.sqlite" >/dev/null; then
  echo "db migrate apply reported success but wrote no database file" >&2
  ls -la .zonai/data 2>/dev/null >&2 || true
  exit 1
fi
echo "  ok: migrations applied against a real database file"

echo "== 2. the ops/rules snapshots spawn as isolates here =="
# `zonai ping` starts every worker, which makes it the cheapest way to reach the
# isolate transport: a bundle carries no source entry, so each mailman spawns its
# .aot snapshot and only falls back to the .exe worker when that fails. It also
# reaches the snapshots on a project-linked bundle, where `serve` would dispatch
# in-process and never touch them.
#
# The ping is not the assertion. Both transports answer it, which is exactly the
# bug: a host-arch snapshot shipped for two releases without a single check going
# red. What is asserted is the fallback warning, and its absence here only counts
# because the control below shows it appearing.
ping_log="$(mktemp)"
if ! ./zonai ping --no-version-check > "$ping_log" 2>&1; then
  echo "  zonai ping failed outright:" >&2
  cat "$ping_log" >&2
  exit 1
fi
for worker in rules operation; do
  if ! grep -q "Ping ${worker} succeeded" "$ping_log"; then
    echo "  ${worker} did not answer a ping:" >&2
    cat "$ping_log" >&2
    exit 1
  fi
done
if grep -q "would not spawn" "$ping_log"; then
  echo "  a snapshot in this bundle would not spawn on ${target_os}/${target_arch}:" >&2
  grep "would not spawn" "$ping_log" >&2
  echo "  Dispatch still works through the worker process, which is why this is" >&2
  echo "  the only place it shows -- the bundle serves identically without" >&2
  echo "  in-process ops and rules." >&2
  exit 1
fi
echo "  ok: rules and operations answered, and neither fell back to its process"

# Positive control. A snapshot that cannot spawn has to produce that warning, or
# the silence just checked is compatible with a tap that never fires. Breaking
# one on purpose is the only way to know which was read.
rules_snapshot=".zonai/executables/db_rules.aot"
if [[ ! -f "$rules_snapshot" ]]; then
  echo "  NOT CHECKED: no ${rules_snapshot}, so the warning this step relies on" >&2
  echo "  was never provoked. The silence above is unproven, not a pass." >&2
else
  snapshot_backup="$(mktemp)"
  cp "$rules_snapshot" "$snapshot_backup"
  # Restore on any exit: leaving a bundle sabotaged would make every later step
  # -- and any reuse of this checkout -- read as a failure of something else.
  trap 'cp "$snapshot_backup" "$rules_snapshot" 2>/dev/null || true' EXIT
  printf 'not a snapshot' > "$rules_snapshot"

  control_log="$(mktemp)"
  ./zonai ping --no-version-check > "$control_log" 2>&1 || true

  cp "$snapshot_backup" "$rules_snapshot"
  trap - EXIT

  if ! grep -q "would not spawn" "$control_log"; then
    echo "  a deliberately broken ${rules_snapshot} produced no warning:" >&2
    cat "$control_log" >&2
    echo "  The check above reads that warning, so without this the silence" >&2
    echo "  there proves nothing about the snapshot that shipped." >&2
    exit 1
  fi
  # The fallback is the reason a wrong snapshot is survivable rather than fatal.
  # If it stops working, this gate should start failing for that instead.
  if ! grep -q "Ping rules succeeded" "$control_log"; then
    echo "  with a broken snapshot, rules stopped answering entirely:" >&2
    cat "$control_log" >&2
    echo "  The .exe worker is meant to take over. That fallback is what makes" >&2
    echo "  a wrong-arch snapshot a slow deploy rather than a broken one." >&2
    exit 1
  fi
  echo "  ok: a broken snapshot warns and falls back, so the check above reads something"
fi

echo "== 3. nothing foreign was installed into the shared library path =="
checked_any=0
for pair in "${resqlite_library}:${before_resqlite}" "${argon2_library}:${before_argon2}"; do
  library="${pair%%:*}"
  before="${pair##*:}"
  path=".zonai/lib/${library}"

  if [[ ! -f "$path" ]]; then
    echo "  (no ${path}: nothing extracted it and none shipped)"
    continue
  fi
  checked_any=1

  # The check that does not depend on anything having shipped: whatever is at
  # the shared path now has to be an object file for THIS platform. A bundle
  # built on macOS that installed its own embedded copy fails here.
  actual_platform="$(object_platform "$path")"
  if [[ "$actual_platform" != "${target_os}/${target_arch}" ]]; then
    echo "  ${path} is a ${actual_platform} object file" >&2
    echo "  expected ${target_os}/${target_arch}." >&2
    echo "  Something in this bundle extracted the build host's library over" >&2
    echo "  the path every process here loads from." >&2
    exit 1
  fi
  echo "  ok: ${path} is a ${actual_platform} object file"

  if [[ -n "$before" ]]; then
    after="$(digest_of "$path")"
    if [[ "$before" != "$after" ]]; then
      echo "  ${path} changed while the bundle ran" >&2
      echo "  before ${before}" >&2
      echo "  after  ${after}" >&2
      echo "  It shipped stamped for this target and something replaced it." >&2
      exit 1
    fi
    echo "  ok: ${path} is byte-identical to what shipped"
  fi
done

if [[ "$checked_any" == "0" ]]; then
  echo "  NOT CHECKED: no library exists at .zonai/lib after the run, so this" >&2
  echo "  step read nothing. That is not a pass -- it means the bundle never" >&2
  echo "  reached the extraction path, and step 1 above is what vouched for it." >&2
fi

echo "== 4. self-extraction refuses a foreign library, keeps a stamped one =="
if [[ -z "$probe" ]]; then
  echo "  NOT CHECKED: no probe was supplied, so the guard's refuse/keep" >&2
  echo "  behaviour was not exercised here at all. cross_target_build.sh builds" >&2
  echo "  one only where apps/zonai/lib/gen/native/*.g.dart exists." >&2
  echo "Cross-target bundle verified on ${target_os}/${target_arch} (step 4 skipped)"
  exit 0
fi

control_dir="$(mktemp -d)"
trap 'rm -rf "$control_dir"' EXIT

# Negative control. The probe is cross-compiled, so its embedded libraries are
# the build host's; with nothing stamped here it must refuse rather than
# install them. A gate that cannot fail proves nothing, and this is the one
# assertion here that can only pass because of the guard.
mkdir -p "${control_dir}/negative"
if (cd "${control_dir}/negative" && "$probe" resqlite > probe.out 2> probe.err); then
  echo "  the probe installed a library it should have refused:" >&2
  cat "${control_dir}/negative/probe.out" >&2
  exit 1
fi
if ! grep -q "Refusing to install" "${control_dir}/negative/probe.err"; then
  echo "  the probe failed, but not with the refusal this gate is about:" >&2
  cat "${control_dir}/negative/probe.err" >&2
  exit 1
fi
if compgen -G "${control_dir}/negative/.zonai/lib/*${library_suffix}" >/dev/null; then
  echo "  the probe refused but left a library behind:" >&2
  ls -la "${control_dir}/negative/.zonai/lib" >&2
  exit 1
fi
echo "  ok: refused, and wrote no library"

# Positive control. The same binary, in a directory where `zonai build` has
# already placed a library stamped for this exact release and target, must keep
# it -- otherwise the refusal above would just as easily be a guard that
# rejects everything, and the bundle in step 1 would work by luck.
mkdir -p "${control_dir}/positive/.zonai/lib"
cp ".zonai/lib/${resqlite_library}" "${control_dir}/positive/.zonai/lib/"
printf '%s %s %s' "$version" "$target_os" "$target_arch" \
  > "${control_dir}/positive/.zonai/lib/${resqlite_library}.stamp"
planted="$(digest_of "${control_dir}/positive/.zonai/lib/${resqlite_library}")"

# A refusal here rather than a path means the stamp did not apply, and the one
# way that happens with a correct library is a version mismatch: the stamp is
# written from VERSION, and the probe compares it against the kVersion compiled
# into itself. They are the same file in CI; they diverge if a probe and a
# VERSION from different checkouts are paired by hand.
if ! reported="$(cd "${control_dir}/positive" && "$probe" resqlite 2>"${control_dir}/positive.err")"; then
  echo "  the probe refused a library stamped '${version} ${target_os} ${target_arch}'" >&2
  echo "  Check that ${version} is the kVersion compiled into this probe --" >&2
  echo "  a stamp naming any other release does not apply." >&2
  cat "${control_dir}/positive.err" >&2
  exit 1
fi
if [[ "$reported" != *".zonai/lib/${resqlite_library}" ]]; then
  echo "  the probe reported ${reported}, not the stamped library" >&2
  exit 1
fi
if [[ "$(digest_of "$reported")" != "$planted" ]]; then
  echo "  the probe overwrote a library stamped '${version} ${target_os} ${target_arch}'" >&2
  exit 1
fi
echo "  ok: kept the stamped library and reported its path"

echo "Cross-target bundle verified on ${target_os}/${target_arch}"
