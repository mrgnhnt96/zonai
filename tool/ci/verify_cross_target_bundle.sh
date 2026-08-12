#!/usr/bin/env bash
# Run a bundle built on another platform (see cross_target_build.sh) on a
# machine of the platform it was built for.
#
# Three things are checked, and they fail for different reasons:
#
#   1. The bundle runs. Migrations apply, which means resqlite was dlopen'd --
#      the check that would have caught a bundle carrying the build host's
#      libraries.
#   2. The stamped libraries are still the ones that shipped. Every executable
#      here extracts to the *same* `.zonai/lib/` path, so one of them getting it
#      wrong replaces the library for all of them; comparing digests before and
#      after is how that shows up as a failure rather than as the next
#      deployment's mystery.
#   3. A cross-compiled binary refuses to install its own embedded libraries
#      here (negative control), and still keeps a correctly stamped one
#      (positive control). Without the negative control this gate would pass
#      just as happily against a build that writes the wrong library, because
#      nothing else here forces the self-extraction path to run.
#
# Usage: verify_cross_target_bundle.sh <bundle-dir> <probe> [version-file]
set -euo pipefail

bundle_dir="${1:?bundle directory required}"
probe="${2:?probe path required}"
version_file="${3:-}"

bundle_dir="$(cd "$bundle_dir" && pwd)"
probe="$(cd "$(dirname "$probe")" && pwd)/$(basename "$probe")"

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

# Artifact upload does not preserve the executable bit.
chmod +x "$probe"
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
before_resqlite="$(digest_of ".zonai/lib/${resqlite_library}")"
before_argon2="$(digest_of ".zonai/lib/${argon2_library}")"

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

echo "== 2. the shipped libraries were not overwritten =="
for pair in "${resqlite_library}:${before_resqlite}" "${argon2_library}:${before_argon2}"; do
  library="${pair%%:*}"
  before="${pair##*:}"
  after="$(digest_of ".zonai/lib/${library}")"
  if [[ "$before" != "$after" ]]; then
    echo "  .zonai/lib/${library} changed while the bundle ran" >&2
    echo "  before ${before}" >&2
    echo "  after  ${after}" >&2
    echo "  Something in the bundle extracted over the stamped library. On a" >&2
    echo "  cross-compiled bundle those bytes are the build host's." >&2
    exit 1
  fi
  echo "  ok: .zonai/lib/${library} is byte-identical after the run"
done

echo "== 3. self-extraction refuses a foreign library, keeps a stamped one =="
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

reported="$(cd "${control_dir}/positive" && "$probe" resqlite)"
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
