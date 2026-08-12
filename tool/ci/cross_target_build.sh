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
# REQUIRE_NATIVE_LIBS=1 makes a bundle without the target's libraries a failure.
# It is off by default because `zonai build` fetches them from the GitHub
# release for *this* version, which does not exist yet while the release that
# would publish it is still being verified. Running before the release can
# therefore only check what does not depend on that download -- which is most
# of what matters, since a bundle without those libraries still deploys (the
# published binary is built for the target and answers its workers' requests).
# The post-release job sets it to 1, where the assets do exist and their absence
# is a real failure.
#
# Usage: cross_target_build.sh <executable> <target-os> <target-arch> [fixture-dir] [out-dir]
set -euo pipefail

require_native_libs="${REQUIRE_NATIVE_LIBS:-0}"

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

# shellcheck source=tool/ci/object_platform.sh
source "${repo_root}/tool/ci/object_platform.sh"

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

# Whether `zonai build` could fetch the target's libraries at all, and if not,
# why -- named out loud rather than left as a quiet absence, because "the
# release has not been cut yet" and "the fetch is broken" look identical in a
# bundle that simply has no lib directory.
report_missing_native_libs() {
  local repo="${GITHUB_REPOSITORY:-mrgnhnt96/zonai}"
  local auth=()
  local token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
  if [[ -n "$token" ]]; then
    auth=(-H "Authorization: Bearer ${token}")
  fi

  local status
  status="$(curl -s -o /dev/null -w '%{http_code}' \
    -H "Accept: application/vnd.github+json" \
    "${auth[@]}" \
    "https://api.github.com/repos/${repo}/releases/tags/v${version}" || echo "000")"

  echo ""
  echo "  NOT CHECKED: the bundle carries no target native libraries."
  case "$status" in
    404)
      echo "  Release v${version} does not exist yet, which is expected before" >&2
      echo "  the release that publishes it. zonai build fetches them from that" >&2
      echo "  release, so there was nothing to fetch." >&2
      ;;
    200)
      echo "  Release v${version} EXISTS, so the fetch should have worked." >&2
      echo "  Check the build log above for the reason it did not." >&2
      ;;
    *)
      echo "  Could not tell whether release v${version} exists (HTTP ${status})." >&2
      echo "  A rate-limited or failed API call reads the same as a missing" >&2
      echo "  release here, so this is stated rather than interpreted." >&2
      ;;
  esac
  echo "  Skipped: the stamp naming this release and target, and the check that" >&2
  echo "  the libraries are ${target_os}/${target_arch} object files." >&2
  echo "  Still checked by the run half: that the bundle runs on the target," >&2
  echo "  that nothing installs a foreign library, and that the guard refuses" >&2
  echo "  one. Set REQUIRE_NATIVE_LIBS=1 to make this absence a failure." >&2
  echo ""
}

# The point of the gate. Absent these, every executable in the bundle falls
# back to the libraries it embedded, which are this host's.
if [[ ! -d build/.zonai/lib ]]; then
  if [[ "$require_native_libs" == "1" ]]; then
    echo "zonai build produced no build/.zonai/lib, and REQUIRE_NATIVE_LIBS=1" >&2
    report_missing_native_libs
    exit 1
  fi
  report_missing_native_libs
fi

# Present is present: if a library shipped in the bundle it has to be right,
# whether or not the fetch was required. Only the *requirement* is conditional.
for library in libresqlite libargon2sodium; do
  library_path="build/.zonai/lib/${library}${library_suffix}"
  if [[ ! -f "$library_path" ]]; then
    if [[ "$require_native_libs" == "1" ]]; then
      echo "zonai build did not produce $library_path" >&2
      exit 1
    fi
    continue
  fi
  echo "  ok: $library_path"

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

  # The only check here that reads the bytes rather than what something claimed
  # about them -- a correct stamp on a host library is the exact failure this
  # gate exists to catch, and is indistinguishable from success without it.
  actual_platform="$(object_platform "$library_path")"
  if [[ "$actual_platform" != "${target_os}/${target_arch}" ]]; then
    echo "  ${library_path} is a ${actual_platform} object file" >&2
    echo "  expected ${target_os}/${target_arch}." >&2
    exit 1
  fi
  echo "  ok: ${library_path} is a ${actual_platform} object file"
done

# The workers are the executables that would self-extract a host library on the
# target, so their presence is what makes the run half meaningful.
for worker in db_operations db_rules; do
  require_file "build/.zonai/executables/${worker}.exe"
done

# Cross-compiled deliberately: this binary embeds the *host's* libraries, which
# is what makes it the negative control on the target. See
# verify_cross_target_bundle.sh.
#
# It can only be built where the embedded-library sources are, which is a
# checkout that has run the generators. Where they are absent the probe is
# skipped by name, and the run half says so too rather than quietly checking
# one thing fewer.
if compgen -G "${repo_root}/apps/zonai/lib/gen/native/*.g.dart" >/dev/null; then
  echo "Compiling the native-library probe for ${target_os}/${target_arch}..."
  (
    cd "${repo_root}/apps/zonai"
    dart compile exe \
      -D__ZONAI_COMPILED__=true \
      --target-os "$target_os" \
      --target-arch "$target_arch" \
      test/support/native_library_probe.dart \
      -o "${out_dir}/native_library_probe"
  )
else
  echo "NOT CHECKED: no apps/zonai/lib/gen/native/*.g.dart in this checkout, so"
  echo "  the probe was not built and the run half cannot exercise the guard's"
  echo "  refuse/keep controls. The bundle itself is still run on the target."
fi

echo "Staging the bundle for the ${target_os}/${target_arch} runner..."
rm -rf "${out_dir}/bundle"
mkdir -p "${out_dir}/bundle"
cp -R build/. "${out_dir}/bundle/"
printf '%s\n' "$version" > "${out_dir}/VERSION"

echo "Cross-target bundle staged at ${out_dir}"
