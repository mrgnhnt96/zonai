#!/usr/bin/env bash
# Resolve the release version from VERSION and the latest GitHub release.
#
# VERSION must be GREATER than the latest CLI release tag. If it is, that is the
# release version. If it is not, this REFUSES -- it does not invent one.
#
# WHY IT REFUSES RATHER THAN BUMPING. It used to bump the latest tag's minor
# whenever VERSION was not ahead, and that turned a routine act into a release:
# compile.yml calls this script, so after any release -- when the release job has
# committed VERSION and it therefore EQUALS the newest tag -- dispatching Compile
# on main resolved a brand-new minor and the chain published it. There is no
# confirmation step in that path and nothing about dispatching Compile says
# "cut 0.9.0". docs/releasing.md has always told humans to bump VERSION by hand
# first; the auto-bump existed only to paper over forgetting, and what it
# actually papered over was intent.
#
# Worse, the two callers resolve INDEPENDENTLY, in separate checkouts:
# compile.yml stamps kVersion into five binaries, and release.yml resolves again
# to pick the tag. Anything that makes them disagree ships binaries whose
# reported version is not the tag they were published under -- which is exactly
# what v0.6.3 did (released binary reported 0.6.2). A rule of "use VERSION, or
# stop" cannot drift between two callers; "bump whatever you find" can.
#
# ESCAPE HATCHES, both explicit and both recorded in the log:
#   RELEASE_VERSION_DRY_RUN=1     Use VERSION as it stands. Never bumps, never
#                                 refuses. For exercising the build on a commit
#                                 that is not a release -- compile.yml exposes
#                                 this as its `dry_run` dispatch input. The
#                                 binaries carry the version already in VERSION,
#                                 and because release.yml resolves WITHOUT this
#                                 flag, the chain a dry run starts cannot
#                                 publish: it stops here, loudly.
#   RELEASE_VERSION_ALLOW_BUMP=1  Restore the old auto-bump. Nothing sets it;
#                                 it exists so reverting this behaviour is a
#                                 decision someone makes on purpose rather than
#                                 a code edit under time pressure.
#
# The first release of a repo is NOT a refusal: with no CLI release to be ahead
# of, there is nothing to accidentally re-release, so the 0.0.0 bootstrap still
# bumps. That path is what a repo with no releases at all takes.
#
# Writes VERSION and apps/zonai/lib/gen/version.dart. Does not commit.
#
# Outputs:
#   GITHUB_OUTPUT version=<semver>  (when GITHUB_OUTPUT is set)
set -euo pipefail

# GitHub passes booleans through as the strings "true"/"false"; a human typing
# this at a shell writes 1. Accept both, and treat everything else as off --
# including the empty string, which is what an unset dispatch input expands to.
is_on() {
  case "${1:-}" in
    1 | true | TRUE | True | yes) return 0 ;;
    *) return 1 ;;
  esac
}

dry_run=0
if is_on "${RELEASE_VERSION_DRY_RUN:-}"; then
  dry_run=1
fi
allow_bump=0
if is_on "${RELEASE_VERSION_ALLOW_BUMP:-}"; then
  allow_bump=1
fi

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
# Assigns `latest_version` and `has_cli_release` directly instead of printing,
# because the caller needs BOTH and a `$(...)` capture would run this in a
# subshell where the second assignment is discarded -- silently, leaving every
# refusal looking like the bootstrap path.
#
# The two answers differ where it matters: "0.0.0" is both the no-releases-yet
# sentinel and a version somebody could in principle have released, and only one
# of those may skip the refusal below.
latest_version="0.0.0"
has_cli_release=0
read_latest_release_version() {
  local latest_tag=""
  if latest_tag="$(bash "${ROOT}/tool/ci/latest_cli_release_tag.sh" 2>/dev/null)"; then
    if [[ -n "${latest_tag}" && "${latest_tag}" != "null" ]]; then
      has_cli_release=1
      latest_version="${latest_tag#v}"
      return
    fi
  fi
  latest_version="0.0.0"
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
read_latest_release_version

require_semver "${repo_version}" "VERSION"
require_semver "${latest_version}" "latest release tag"

if version_gt "${repo_version}" "${latest_version}"; then
  # The ordinary path, and the only one that needs no explanation: somebody
  # bumped VERSION, and this is that release.
  target_version="${repo_version}"
elif [[ "${has_cli_release}" -eq 0 ]]; then
  # First release. Nothing to re-release, so the bootstrap keeps working.
  target_version="$(bump_minor "${latest_version}")"
  echo "No CLI release exists yet; bootstrapping to ${target_version}."
elif [[ "${dry_run}" -eq 1 ]]; then
  target_version="${repo_version}"
  echo "DRY RUN: VERSION (${repo_version}) is not ahead of the latest release" \
    "(${latest_version}), and is being used unchanged."
  echo "Nothing here bumps it, and release.yml resolves without this flag --" \
    "so the chain this starts will refuse to publish rather than tag" \
    "${repo_version} a second time."
elif [[ "${allow_bump}" -eq 1 ]]; then
  target_version="$(bump_minor "${latest_version}")"
  echo "RELEASE_VERSION_ALLOW_BUMP is set: bumping the latest release" \
    "(${latest_version}) to ${target_version} rather than refusing."
else
  {
    echo "REFUSING to resolve a release version."
    echo
    echo "  VERSION            : ${repo_version}"
    echo "  latest CLI release : ${latest_version}"
    echo
    echo "VERSION must be GREATER than the latest release to publish, and it is"
    echo "not. This script will not invent a version, because the only caller"
    echo "that reaches here without meaning to is a Compile dispatched on main"
    echo "after a release -- and inventing one there publishes a release nobody"
    echo "asked for."
    echo
    echo "If you meant to release: bump VERSION (see docs/releasing.md), commit"
    echo "it, and dispatch Compile on that commit."
    echo
    echo "If you meant to exercise the build: dispatch Compile with dry_run"
    echo "enabled, which builds against VERSION as it stands and cannot publish."
  } >&2
  exit 1
fi

write_version_files "${target_version}"

echo "Resolved release version: ${target_version} (repo: ${repo_version}, latest release: ${latest_version})"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "version=${target_version}" >> "${GITHUB_OUTPUT}"
fi
