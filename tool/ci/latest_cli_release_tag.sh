#!/usr/bin/env bash
# Prints the newest zonai CLI release tag (`v<semver>`), or nothing at all when
# the repo has none yet.
#
# GitHub's own "latest" cannot be used for this. This repo publishes
# per-package releases alongside the CLI's -- zonai_schema-v0.1.0 and
# zonai_client-v0.1.0 landed on 2026-08-10 -- and "latest" is simply the most
# recent non-draft, non-prerelease release of any kind. When a package release
# takes that slot it breaks three separate things at once, all silently:
# the version resolver bumped `zonai_schema-v0.1.0` into the literal string
# `zonai_schema-v0.2.0`; verify-release's compat check downloaded from it and
# got "no assets to download"; and every releases/latest/download link in the
# docs started 404ing.
#
# Releases come back newest-first, so the first match is the latest CLI one.
# draft/prerelease are excluded to keep /releases/latest's semantics -- the
# plain list endpoint returns drafts to a token that can see them, and a draft
# v9.9.9 sitting in the repo would otherwise win.
#
# Usage: latest_cli_release_tag.sh [owner/repo]
set -euo pipefail

repo="${1:-${GITHUB_REPOSITORY:-}}"
if [[ -z "${repo}" ]]; then
  echo "repository required (argument or GITHUB_REPOSITORY)" >&2
  exit 1
fi

gh api "repos/${repo}/releases?per_page=100" \
  -q '[.[] | select(.draft == false and .prerelease == false)
           | select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))]
      | .[0].tag_name // empty'
