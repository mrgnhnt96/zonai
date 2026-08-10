#!/usr/bin/env bash
# Package per-target native libraries into release zips.
#
# `dart compile exe --target-os` cross-compiles the executable format but NOT
# the native-library bytes embedded in the binary: those are Dart constants
# baked in by whatever host ran the build (see the comment on
# apps/zonai/lib/src/native/resqlite_native.dart's _requestFromSpawner). A
# host binary cross-compiled on macOS therefore self-extracts a .dylib onto
# the Linux machine it runs on. Shipping the libraries per target lets a
# cross-target `zonai build` place correct ones beside the binary instead.
#
# These come from the *compile* run's artifacts, not from native-libs.yml
# directly, so they are byte-for-byte the libraries embedded in the binaries
# released alongside them. Pulling both from "latest successful run" of two
# different workflows would let a native-libs.yml run landing in between ship
# libraries that disagree with the binaries -- and since the on-disk copy
# overrides the embedded one, that mismatch would be silent.
#
# Usage: package_native_lib_assets.sh <artifacts-dir> [output-dir]
#
# Expects artifact layout from compile workflow downloads:
#   <artifacts-dir>/native-libs-embedded-linux-x64/libresqlite.so
#   <artifacts-dir>/native-libs-embedded-linux-x64/libargon2sodium.so
#   ... and so on per target, with .dylib on macOS and bare .dll on Windows.
set -euo pipefail

artifacts_dir="${1:?artifacts directory required}"
output_dir="${2:-release-assets}"

mkdir -p "${output_dir}"

pack() {
  local target="$1"
  shift

  local source_dir="${artifacts_dir}/native-libs-embedded-${target}"
  if [[ ! -d "${source_dir}" ]]; then
    echo "missing native library artifact: ${source_dir}" >&2
    exit 1
  fi

  local library
  for library in "$@"; do
    if [[ ! -f "${source_dir}/${library}" ]]; then
      echo "missing native library: ${source_dir}/${library}" >&2
      exit 1
    fi
  done

  local absolute_source
  absolute_source="$(cd "${source_dir}" && pwd)"

  (
    cd "${absolute_source}"
    # -X drops extended attributes/timestamps so the same inputs zip to the
    # same bytes, which keeps a re-run from producing a "changed" asset.
    zip -q -X "${OLDPWD}/${output_dir}/native-libs-${target}.zip" "$@"
  )
  echo "Packaged native-libs-${target}.zip ($*)"
}

pack "linux-x64" "libresqlite.so" "libargon2sodium.so"
pack "linux-arm64" "libresqlite.so" "libargon2sodium.so"
pack "macos-arm64" "libresqlite.dylib" "libargon2sodium.dylib"
pack "macos-x64" "libresqlite.dylib" "libargon2sodium.dylib"
pack "windows-x64" "resqlite.dll" "argon2sodium.dll"
