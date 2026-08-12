#!/usr/bin/env bash
# Build a deployable bundle for a platform this machine is NOT, and prove the
# bundle carries the target's own native libraries.
#
# verify_build_command.sh covers the host-target build. It cannot cover this
# one: `dart compile exe --target-os` cross-compiles the executable format but
# not the native-library bytes embedded as Dart constants, so every executable
# a macOS host emits for Linux -- the bundled host binary and all six workers --
# carries Mach-O libraries inside it. Whether the bundle is deployable depends
# entirely on what `zonai build` puts in `build/.zonai/lib/` beside them, and
# that step ran only on the project-linked branch until this gate existed.
#
# Only the assembling half runs here. Running the bundle needs a machine of the
# target platform, which is verify_cross_target_bundle.sh on a runner of that
# platform -- the two halves cannot be one job, and GitHub's macOS runners have
# no container runtime to fake it with.
#
# Usage: cross_target_build.sh <executable> <target-os> <target-arch> [fixture-dir] [out-dir]
set -euo pipefail

executable="${1:?executable path required}"
target_os="${2:?target os required}"
target_arch="${3:?target arch required}"
fixture_dir="${4:-e2e/build_smoke}"
out_dir="${5:-cross-target-out}"

executable="$(cd "$(dirname "$executable")" && pwd)/$(basename "$executable")"
if [[ ! -x "$executable" ]]; then
  chmod +x "$executable"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_dir="$(mkdir -p "$out_dir" && cd "$out_dir" && pwd)"

host_os="$(uname -s)"
case "$host_os" in
  Darwin) host_os=macos ;;
  Linux) host_os=linux ;;
  *) host_os="$(echo "$host_os" | tr '[:upper:]' '[:lower:]')" ;;
esac
if [[ "$host_os" == "$target_os" ]]; then
  echo "This gate is about cross-compiling; host and target are both ${host_os}." >&2
  echo "Run it on a host of a different OS, or drop the job for this matrix leg." >&2
  exit 1
fi

version="$(tr -d '[:space:]' < "${repo_root}/VERSION")"
if [[ -z "$version" ]]; then
  echo "VERSION is empty, so nothing can say what a stamp should read" >&2
  exit 1
fi

case "$target_os" in
  linux) library_suffix=.so ;;
  macos) library_suffix=.dylib ;;
  windows) library_suffix=.dll ;;
  *) echo "Unsupported target os: ${target_os}" >&2; exit 1 ;;
esac

cd "${repo_root}/${fixture_dir}"

# zonai.yaml is the only place a build target can be set, so the fixture has to
# be edited in place and put back -- a gate that leaves the working tree
# retargeted would change what every later job builds.
settings_backup="$(mktemp)"
cp zonai.yaml "$settings_backup"
restore_settings() { cp "$settings_backup" zonai.yaml; rm -f "$settings_backup"; }
trap restore_settings EXIT

printf '\nbuildSettings:\n  targetOs: %s\n  targetArch: %s\n' \
  "$target_os" "$target_arch" >> zonai.yaml

rm -rf build .zonai

echo "Resolving fixture dependencies..."
dart pub get

echo "Generating a migration so the bundle has one to apply on the target..."
"$executable" db migrate generate --name initialize --no-version-check

echo "Building for ${target_os}/${target_arch} on ${host_os}..."
"$executable" build --no-version-check

require_file() {
  if [[ ! -f "$1" ]]; then
    echo "zonai build did not produce $1" >&2
    ls -la "$(dirname "$1")" >&2 || true
    exit 1
  fi
  echo "  ok: $1"
}

built_name="zonai"
if [[ "$target_os" == windows ]]; then
  built_name="zonai.exe"
fi
require_file "build/${built_name}"

# The point of the gate. Absent these, every executable in the bundle falls
# back to the libraries it embedded, which are this host's.
for library in libresqlite libargon2sodium; do
  library_path="build/.zonai/lib/${library}${library_suffix}"
  require_file "$library_path"

  stamp_path="${library_path}.stamp"
  require_file "$stamp_path"

  expected_stamp="${version} ${target_os} ${target_arch}"
  actual_stamp="$(tr -d '\n' < "$stamp_path")"
  if [[ "$actual_stamp" != "$expected_stamp" ]]; then
    echo "  ${stamp_path} reads '${actual_stamp}', expected '${expected_stamp}'" >&2
    echo "  A stamp naming anything else stops applying on the target, and the" >&2
    echo "  binary reading it falls back to its own embedded copy." >&2
    exit 1
  fi
  echo "  ok: ${stamp_path} reads '${actual_stamp}'"

  # `file` is the only check here that reads the bytes rather than what
  # something claimed about them -- a correct stamp on a host library is the
  # exact failure this gate exists to catch, and is indistinguishable from
  # success without it.
  description="$(file -b "$library_path")"
  case "$target_os/$target_arch" in
    linux/x64) expected_format="ELF 64-bit LSB shared object, x86-64" ;;
    linux/arm64) expected_format="ELF 64-bit LSB shared object, ARM aarch64" ;;
    *) expected_format="" ;;
  esac
  if [[ -n "$expected_format" && "$description" != *"$expected_format"* ]]; then
    echo "  ${library_path} is '${description}'" >&2
    echo "  expected it to contain '${expected_format}'" >&2
    exit 1
  fi
  echo "  ok: ${library_path} is ${description%%,*}"
done

# The workers are the executables that would self-extract a host library on the
# target, so their presence is what makes the run half meaningful.
for worker in db_operations db_rules; do
  require_file "build/.zonai/executables/${worker}.exe"
done

echo "Compiling the native-library probe for ${target_os}/${target_arch}..."
# Cross-compiled deliberately: this binary embeds the *host's* libraries, which
# is what makes it the negative control on the target. See
# verify_cross_target_bundle.sh.
(
  cd "${repo_root}/apps/zonai"
  dart compile exe \
    -D__ZONAI_COMPILED__=true \
    --target-os "$target_os" \
    --target-arch "$target_arch" \
    test/support/native_library_probe.dart \
    -o "${out_dir}/native_library_probe"
)

echo "Staging the bundle for the ${target_os}/${target_arch} runner..."
rm -rf "${out_dir}/bundle"
mkdir -p "${out_dir}/bundle"
cp -R build/. "${out_dir}/bundle/"
printf '%s\n' "$version" > "${out_dir}/VERSION"

echo "Cross-target bundle staged at ${out_dir}"
