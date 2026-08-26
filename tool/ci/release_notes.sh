#!/usr/bin/env bash
# The curated summary that ships as a release's description, and the gate that
# refuses to publish without one.
#
# WHAT THIS EXISTS FOR. Every release through v0.8.4 was PUBLISHED with
# `--generate-notes` and nothing else, so what went out was one line:
# `**Full Changelog**: .../compare/v0.8.3...v0.8.4`. That is a diff, not a
# summary -- it tells somebody deciding whether to upgrade to go read 90
# commits, most of which are `test:` and `chore:`. The release page is the only
# place a consumer of the CLI ever looks.
#
# WHY IT IS A TRACKED FILE AND NOT A STEP IN A CHECKLIST. Some releases did get
# a real summary -- v0.7.0, v0.8.0 and v0.8.1 carry hand-written highlights,
# added by editing the release AFTER it published. So the miss was never
# "nobody wanted one": v0.8.2, v0.8.3 and v0.8.4 simply went out on days when
# the release was the busy part, and nothing anywhere said otherwise. That is
# the failure mode of a step that lives only in docs/releasing.md, exactly like
# `sync_playground_version.sh`, which the flow was told to call and nothing did
# for eleven versions.
#
# Tying the file to VERSION makes forgetting it a refusal instead: bumping
# VERSION without touching RELEASE_NOTES.md fails `check`, `check` runs in
# `static` on the branch, and it runs again in release.yml's gate job before
# anything is packaged.
#
# WHY --notes-file AND NOT --generate-notes. The two can be combined, but what
# gh does when they are is a property of gh, resolved at release time on a
# runner, and the cost of getting it wrong is a published description that
# cannot be un-published (it can be edited, but the notification and the feed
# entry carry the original). Building the whole body here -- summary, then the
# compare link generate-notes would have produced -- is one behaviour, testable
# on a laptop, with no dependency on which gh the runner happens to ship.
#
# WHAT IT CANNOT CHECK, out loud: whether the summary is TRUE, or whether it
# describes this version rather than the last one with the heading changed.
# It checks that a human wrote something, bulleted, under the right number.
# The judgement is still the human's; this only makes skipping it loud.
#
# Usage:
#   release_notes.sh check              validate RELEASE_NOTES.md against VERSION
#   release_notes.sh body <tag> <prev>  print the release description for <tag>
#
# `check` takes no arguments and reads VERSION itself, so the gate and the
# release cannot disagree about which version is being described.
set -euo pipefail

root="${RELEASE_NOTES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
notes="${root}/RELEASE_NOTES.md"
version_file="${root}/VERSION"

# The section for one version: everything after `## <version>` up to the next
# `## `, blank lines at either end trimmed. awk rather than sed -n '/../,/../p'
# because that form includes the closing match, and the closing match here is
# the NEXT release's heading.
section_for() {
  local want="$1"
  awk -v want="${want}" '
    /^## / {
      # `## 0.8.5` and `## 0.8.5 -- anything` both name 0.8.5; the heading is
      # allowed a human-readable tail so a release can be titled.
      split($0, parts, " ")
      in_section = (parts[2] == want)
      next
    }
    in_section { lines[++n] = $0 }
    END {
      # Trim blank lines off both ends: the heading is always followed by one,
      # and a trailing one would put a stray newline in the published body.
      first = 1; while (first <= n && lines[first] ~ /^[[:space:]]*$/) first++
      last = n;  while (last >= first && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = first; i <= last; i++) print lines[i]
    }
  ' "${notes}"
}

require_notes_file() {
  if [[ ! -f "${notes}" ]]; then
    cat >&2 <<EOF
No RELEASE_NOTES.md at the repo root.

Every release ships a short bulleted summary of what it contains. Create the
file with a section for the version in VERSION:

  ## <version>

  - the first thing this release does
  - the second thing

See docs/releasing.md, "The release summary".
EOF
    exit 1
  fi
}

cmd_check() {
  require_notes_file

  if [[ ! -f "${version_file}" ]]; then
    echo "No VERSION file at ${version_file}" >&2
    exit 1
  fi

  local version
  version="$(tr -d '[:space:]' < "${version_file}")"
  if [[ ! "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "VERSION must be a bare semver, got '${version}'" >&2
    exit 1
  fi

  # The FIRST heading, not merely a matching one anywhere in the file. The file
  # accumulates newest-first, and a summary for the version being released that
  # sits below three older ones means the newest section was never written --
  # which is the exact miss this gate is for.
  local first
  first="$(awk '/^## /{split($0, p, " "); print p[2]; exit}' "${notes}")"
  if [[ "${first}" != "${version}" ]]; then
    cat >&2 <<EOF
RELEASE_NOTES.md does not describe the version being released.

  VERSION                     ${version}
  newest RELEASE_NOTES.md ##  ${first:-<none>}

Add a section at the TOP of RELEASE_NOTES.md, above the previous one:

  ## ${version}

  - what this release does

See docs/releasing.md, "The release summary".
EOF
    exit 1
  fi

  local body
  body="$(section_for "${version}")"
  if ! grep -qE '^[[:space:]]*[-*] +[^[:space:]]' <<< "${body}"; then
    cat >&2 <<EOF
RELEASE_NOTES.md's '## ${version}' section carries no bullets.

The summary is a SHORT LIST, not a paragraph -- somebody deciding whether to
upgrade reads it in ten seconds or not at all:

  ## ${version}

  - what this release does
  - and the other thing

See docs/releasing.md, "The release summary".
EOF
    exit 1
  fi

  echo "RELEASE_NOTES.md describes ${version}:"
  sed 's/^/  /' <<< "${body}"
}

cmd_body() {
  local tag="${1:?tag required (e.g. v0.8.5)}"
  local prev="${2:-}"
  local repo="${3:-${GITHUB_REPOSITORY:-}}"
  local version="${tag#v}"

  require_notes_file

  local body
  body="$(section_for "${version}")"
  if [[ -z "${body//[[:space:]]/}" ]]; then
    echo "RELEASE_NOTES.md has no '## ${version}' section" >&2
    exit 1
  fi

  printf '%s\n' "${body}"

  # The line `--generate-notes` used to produce on its own. Kept because it is
  # the only thing in the old descriptions anybody could have linked to, and
  # because the summary deliberately does not list every commit.
  if [[ -n "${prev}" && -n "${repo}" ]]; then
    printf '\n**Full Changelog**: https://github.com/%s/compare/%s...%s\n' \
      "${repo}" "${prev}" "${tag}"
  fi
}

case "${1:-}" in
  check) shift; cmd_check "$@" ;;
  body)  shift; cmd_body "$@" ;;
  *)
    echo "usage: release_notes.sh {check | body <tag> [prev-tag] [owner/repo]}" >&2
    exit 2
    ;;
esac
