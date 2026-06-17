#!/usr/bin/env bash
# Sync apps/playground/zonai.yaml version with the compiled release VERSION.
#
# Usage: sync_playground_version.sh [playground-dir] [version-file]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
playground_dir="${1:-apps/playground}"
version_file="${2:-${ROOT}/VERSION}"
zonai_yaml="${ROOT}/${playground_dir}/zonai.yaml"

if [[ ! -f "${version_file}" ]]; then
  echo "version file not found: ${version_file}" >&2
  exit 1
fi

if [[ ! -f "${zonai_yaml}" ]]; then
  echo "playground config not found: ${zonai_yaml}" >&2
  exit 1
fi

version="$(tr -d '[:space:]' < "${version_file}")"
perl -pi -e "s/^version: .*/version: ${version}/" "${zonai_yaml}"
echo "Synced ${zonai_yaml} version to ${version}"
