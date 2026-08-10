#!/usr/bin/env bash
# Resolve the release version from VERSION and the latest GitHub release.
#
# If VERSION is greater than the latest release tag, use VERSION.
# Otherwise bump the minor version of the latest release (handles same/lower).
#
# Writes VERSION and apps/zonai/lib/gen/version.dart. Does not commit.
#
# Outputs:
#   GITHUB_OUTPUT version=<semver>  (when GITHUB_OUTPUT is set)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION_FILE="${ROOT}/VERSION"
GEN_FILE="${ROOT}/apps/zonai/lib/gen/version.dart"

read_repo_version() {
  tr -d '[:space:]' < "${VERSION_FILE}"
}

# Taking the newest release of *any* kind resolved the CLI version to
# `zonai_schema-v0.1.0`, which bump_minor then turned into the literal string
# `zonai_schema-v0.2.0` and wrote into VERSION and kVersion. See
# latest_cli_release_tag.sh for why GitHub's "latest" cannot be trusted here.
#
# No tag (a repo with no CLI release yet) falls back to 0.0.0, which is the
# bootstrap path for a first release -- not an error.
read_latest_release_version() {
  local latest_tag=""
  if latest_tag="$(bash "${ROOT}/tool/ci/latest_cli_release_tag.sh" 2>/dev/null)"; then
    if [[ -n "${latest_tag}" && "${latest_tag}" != "null" ]]; then
      echo "${latest_tag#v}"
      return
    fi
  fi
  echo "0.0.0"
}

# Belt and braces for the same class of bug: every consumer below does either
# version comparison or arithmetic, and both silently produce nonsense on a
# non-semver input rather than failing.
require_semver() {
  local value="$1"
  local label="$2"
  if [[ ! "${value}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "${label} is not a semver version: '${value}'" >&2
    exit 1
  fi
}

version_gt() {
  local a="$1"
  local b="$2"
  [[ "${a}" == "$(printf '%s\n' "${a}" "${b}" | sort -V | tail -n1)" && "${a}" != "${b}" ]]
}

bump_minor() {
  local v="$1"
  local major minor
  IFS='.' read -r major minor _ <<< "${v}"
  major="${major:-0}"
  minor="${minor:-0}"
  echo "${major}.$((minor + 1)).0"
}

write_version_files() {
  local version="$1"
  echo "${version}" > "${VERSION_FILE}"
  mkdir -p "$(dirname "${GEN_FILE}")"
  echo "const kVersion = \"${version}\";" > "${GEN_FILE}"
}

repo_version="$(read_repo_version)"
latest_version="$(read_latest_release_version)"

require_semver "${repo_version}" "VERSION"
require_semver "${latest_version}" "latest release tag"

if version_gt "${repo_version}" "${latest_version}"; then
  target_version="${repo_version}"
else
  target_version="$(bump_minor "${latest_version}")"
fi

write_version_files "${target_version}"

echo "Resolved release version: ${target_version} (repo: ${repo_version}, latest release: ${latest_version})"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "version=${target_version}" >> "${GITHUB_OUTPUT}"
fi
