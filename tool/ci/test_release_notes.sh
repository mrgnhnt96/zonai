#!/usr/bin/env bash
# Exercises release_notes.sh against throwaway trees.
#
# It runs on a laptop in milliseconds, which is the point: the thing it guards
# is a description that gets PUBLISHED, and a bug found on the runner is found
# after the release page already says the wrong thing. The cases below are the
# three ways the gate can be wrong in the expensive direction -- passing a
# release whose notes were never written (heading left at the last version,
# section present but empty of bullets, section buried under a newer one) --
# plus the body it hands to the release step.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${repo_root}/tool/ci/release_notes.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/relnotes.XXXXXX")"
trap 'rm -rf "${work}"' EXIT

failures=0

# Builds ${work}/<name> with a VERSION and a RELEASE_NOTES.md read from stdin.
# Not `dir="$(make_tree ...)"` with the heredoc outside: a here-document body
# cannot live outside the command substitution that opened it, and bash reports
# that as `-: command not found` from a line that looks fine.
make_tree() {
  local name="$1" version="$2"
  local dir="${work}/${name}"
  mkdir -p "${dir}"
  printf '%s\n' "${version}" > "${dir}/VERSION"
  cat > "${dir}/RELEASE_NOTES.md"
}

expect_ok() {
  local what="$1" dir="$2"
  if RELEASE_NOTES_ROOT="${dir}" bash "${script}" check >/dev/null 2>&1; then
    echo "ok: ${what}"
  else
    echo "FAIL: ${what} -- check refused a valid file" >&2
    RELEASE_NOTES_ROOT="${dir}" bash "${script}" check >&2 || true
    failures=$((failures + 1))
  fi
}

expect_refusal() {
  local what="$1" dir="$2" needle="$3" out
  if out="$(RELEASE_NOTES_ROOT="${dir}" bash "${script}" check 2>&1)"; then
    echo "FAIL: ${what} -- check PASSED and should not have" >&2
    failures=$((failures + 1))
    return
  fi
  if ! grep -qF "${needle}" <<< "${out}"; then
    echo "FAIL: ${what} -- refused, but the message never said '${needle}':" >&2
    sed 's/^/    /' >&2 <<< "${out}"
    failures=$((failures + 1))
    return
  fi
  echo "ok: ${what}"
}

make_tree good 1.2.3 <<'MD'
# Release notes

## 1.2.3

- the thing this release does
- the other thing

## 1.2.2

- what the last one did
MD
good="${work}/good"
expect_ok "a section for VERSION, with bullets" "${good}"

# THE MISS THIS GATE IS FOR: VERSION moved, the notes did not.
make_tree stale 1.2.3 <<'MD'
# Release notes

## 1.2.2

- what the last one did
MD
stale="${work}/stale"
expect_refusal "notes still describe the previous version" "${stale}" \
  "does not describe the version being released"

# A section that exists but says nothing is the same miss wearing a heading.
make_tree empty 1.2.3 <<'MD'
# Release notes

## 1.2.3

## 1.2.2

- what the last one did
MD
empty="${work}/empty"
expect_refusal "section carries no bullets" "${empty}" "carries no bullets"

# Prose under the heading is not a summary either -- the whole ask is a LIST.
make_tree prose 1.2.3 <<'MD'
# Release notes

## 1.2.3

This release contains a number of improvements and bug fixes.
MD
prose="${work}/prose"
expect_refusal "section is prose, not bullets" "${prose}" "carries no bullets"

# Buried: the right version is described, but an older section sits above it,
# which means the newest one was never written. `check` reads the FIRST
# heading precisely so this is a refusal rather than a pass.
make_tree buried 1.2.3 <<'MD'
# Release notes

## 1.2.2

- what the last one did

## 1.2.3

- the thing this release does
MD
buried="${work}/buried"
expect_refusal "the version's section is not the newest" "${buried}" \
  "does not describe the version being released"

# A titled heading is still a heading for that version.
make_tree titled 1.2.3 <<'MD'
# Release notes

## 1.2.3 -- the one with the tokens

- the thing this release does
MD
titled="${work}/titled"
expect_ok "heading with a human-readable tail" "${titled}"

# The body handed to the release step: the section, then the compare link that
# `--generate-notes` used to be the only source of.
body="$(RELEASE_NOTES_ROOT="${good}" bash "${script}" body v1.2.3 v1.2.2 owner/repo)"
if grep -qF -e "- the thing this release does" <<< "${body}" \
  && grep -qF -e "https://github.com/owner/repo/compare/v1.2.2...v1.2.3" <<< "${body}"; then
  echo "ok: body carries the summary and the compare link"
else
  echo "FAIL: body was not what the release step needs:" >&2
  sed 's/^/    /' >&2 <<< "${body}"
  failures=$((failures + 1))
fi

# It must not bleed the NEXT section in. `## 1.2.2`'s bullet reads plausibly,
# so a greedy range would ship the last release's summary under this tag.
if grep -qF "what the last one did" <<< "${body}"; then
  echo "FAIL: body leaked the previous version's section" >&2
  failures=$((failures + 1))
else
  echo "ok: body stops at the next heading"
fi

if [[ "${failures}" -ne 0 ]]; then
  echo "${failures} release-notes check(s) failed" >&2
  exit 1
fi
echo "release_notes.sh: all checks passed"
