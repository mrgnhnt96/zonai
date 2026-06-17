#!/usr/bin/env bash
# Package compiled zonai binaries into release zips.
#
# Usage: package_release_assets.sh <artifacts-dir> [output-dir]
#
# Expects artifact layout from compile workflow downloads:
#   <artifacts-dir>/zonai-linux-x64/zonai
#   <artifacts-dir>/zonai-macos-arm64/zonai
#   <artifacts-dir>/zonai-macos-x64/zonai
#   <artifacts-dir>/zonai-windows-x64/zonai.exe
set -euo pipefail

artifacts_dir="${1:?artifacts directory required}"
output_dir="${2:-release-assets}"

mkdir -p "${output_dir}"

pack() {
  local zip_name="$1"
  local binary_path="$2"

  if [[ ! -f "${binary_path}" ]]; then
    echo "missing release binary: ${binary_path}" >&2
    exit 1
  fi

  local binary_dir binary_name
  binary_dir="$(cd "$(dirname "${binary_path}")" && pwd)"
  binary_name="$(basename "${binary_path}")"

  (
    cd "${binary_dir}"
    zip -q -X "${OLDPWD}/${output_dir}/${zip_name}" "${binary_name}"
  )
  echo "Packaged ${zip_name}"
}

pack "zonai-linux-x64.zip" "${artifacts_dir}/zonai-linux-x64/zonai"
pack "zonai-macos-arm64.zip" "${artifacts_dir}/zonai-macos-arm64/zonai"
pack "zonai-macos-x64.zip" "${artifacts_dir}/zonai-macos-x64/zonai"
pack "zonai-windows-x64.zip" "${artifacts_dir}/zonai-windows-x64/zonai.exe"
