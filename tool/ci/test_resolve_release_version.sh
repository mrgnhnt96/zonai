#!/usr/bin/env bash
# Exercises resolve_release_version.sh against realistic GitHub payloads.
#
# The bug this exists for: the resolver took the newest release of ANY kind.
# Once this repo started publishing per-package releases (zonai_schema-v0.1.0,
# zonai_client-v0.1.0 on 2026-08-10), the newest release was no longer the CLI's,
# and `bump_minor` turned the tag `zonai_schema-v0.1.0` into the literal string
# `zonai_schema-v0.2.0`, which then went into VERSION and kVersion.
#
# `gh` is stubbed with a script that applies the real `-q` expression to a
# fixture using jq -- so the jq filter itself, the part that was wrong, is what
# gets tested, not a stand-in for it. The resolver runs against a throwaway tree
# so it can write VERSION/version.dart without touching the repo.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to test the release-tag filter" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/tree/tool/ci" "${work}/tree/apps/zonai/lib/gen" "${work}/bin"
cp "${repo_root}/tool/ci/resolve_release_version.sh" "${work}/tree/tool/ci/"
# resolve_release_version.sh shells out to this for the tag; the copy has to
# come along or the resolver silently falls back to its 0.0.0 bootstrap.
cp "${repo_root}/tool/ci/latest_cli_release_tag.sh" "${work}/tree/tool/ci/"

# Newest-first, exactly as the API returns it: the two package releases sit
# above the CLI's, which is what made "take the first one" wrong.
cat > "${work}/releases.json" <<'JSON'
[
  {"tag_name": "zonai_schema-v0.1.0", "draft": false, "prerelease": false},
  {"tag_name": "zonai_client-v0.1.0", "draft": false, "prerelease": false},
  {"tag_name": "v0.6.0", "draft": false, "prerelease": false},
  {"tag_name": "v0.5.2", "draft": false, "prerelease": false}
]
JSON

cat > "${work}/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stand-in for `gh api <endpoint> -q <expr>`: applies the real jq expression to
# the fixture so the filter under test is the one that runs.
expr=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -q) shift; expr="${1:-}" ;;
  esac
  shift || true
done
[[ -n "${expr}" ]] || exit 1
jq -r "${expr}" "${GH_FIXTURE}"
STUB
chmod +x "${work}/bin/gh"

# Any VAR=value pairs after the version are exported for that run only, which
# is how the two escape hatches get exercised without leaking into the next case.
run_resolver() {
  local repo_version="$1"
  shift
  echo "${repo_version}" > "${work}/tree/VERSION"
  (
    export PATH="${work}/bin:${PATH}"
    export GH_FIXTURE="${work}/releases.json"
    export GITHUB_REPOSITORY="mrgnhnt96/zonai"
    unset GITHUB_OUTPUT
    unset RELEASE_VERSION_DRY_RUN RELEASE_VERSION_ALLOW_BUMP
    local pair
    for pair in "$@"; do
      export "${pair?}"
    done
    bash "${work}/tree/tool/ci/resolve_release_version.sh" >/dev/null
  )
  tr -d '[:space:]' < "${work}/tree/VERSION"
}

# Succeeds when the resolver REFUSES. Returns its stderr so a case can assert
# the message names the way out -- a refusal nobody can act on is a dead end,
# and this one is reached by people who did not know they were near a release.
refusal_of() {
  local repo_version="$1"
  shift
  echo "${repo_version}" > "${work}/tree/VERSION"
  local err="${work}/refusal.err"
  if (
    export PATH="${work}/bin:${PATH}"
    export GH_FIXTURE="${work}/releases.json"
    export GITHUB_REPOSITORY="mrgnhnt96/zonai"
    unset GITHUB_OUTPUT
    unset RELEASE_VERSION_DRY_RUN RELEASE_VERSION_ALLOW_BUMP
    local pair
    for pair in "$@"; do
      export "${pair?}"
    done
    bash "${work}/tree/tool/ci/resolve_release_version.sh" >/dev/null 2>"${err}"
  ); then
    return 1
  fi
  cat "${err}"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# 1. A patch bump ahead of the latest CLI release is honoured -- and must not be
#    dragged to some package release's tag.
got="$(run_resolver 0.6.1)"
[[ "${got}" == "0.6.1" ]] || fail "expected 0.6.1 from a repo version ahead of v0.6.0, got '${got}'"

# 2. A repo version at or behind the latest CLI release is a REFUSAL, not a
#    bump. This is the case that made dispatching Compile on main after a
#    release publish a new minor nobody asked for: the release job commits
#    VERSION, so VERSION equals the newest tag from then until someone bumps it.
if ! err="$(refusal_of 0.6.0)"; then
  fail "resolver did not refuse a VERSION equal to the latest release"
fi
[[ "${err}" == *"REFUSING"* ]] || fail "refusal did not say so: '${err}'"
# A refusal that does not name the way out just moves the confusion. Both doors
# are asserted because both are reached by people who did not know they were
# one dispatch away from a release.
[[ "${err}" == *"bump VERSION"* ]] || fail "refusal does not name the release path"
[[ "${err}" == *"dry_run"* ]] || fail "refusal does not name the dry-run path"
# The refusal must leave VERSION ALONE. Rewriting it on the way out would hand
# the next run a version the first one refused to use.
[[ "$(tr -d '[:space:]' < "${work}/tree/VERSION")" == "0.6.0" ]] \
  || fail "a refusal rewrote VERSION"

# 3. kVersion has to follow VERSION, since the two are compared at runtime.
got="$(run_resolver 0.6.1)"
[[ "${got}" == "0.6.1" ]] || fail "expected 0.6.1, got '${got}'"
grep -q 'const kVersion = "0.6.1";' "${work}/tree/apps/zonai/lib/gen/version.dart" \
  || fail "version.dart was not written to match VERSION"

# 4. Only package releases exist: filtering them all out must land on the
#    no-releases-yet bootstrap (0.0.0), NOT on a package tag. Refusing here
#    would be wrong -- it is the same path a repo with no releases at all takes,
#    and that has to keep working for a first release.
cat > "${work}/releases.json" <<'JSON'
[
  {"tag_name": "zonai_schema-v0.1.0", "draft": false, "prerelease": false}
]
JSON
got="$(run_resolver 0.0.0)"
[[ "${got}" == "0.1.0" ]] || fail "expected the 0.0.0 bootstrap to bump to 0.1.0, got '${got}'"
[[ "${got}" != *zonai_* ]] || fail "a package release tag leaked into the version: '${got}'"

# 5. Drafts and prereleases are not releases to bump from -- /releases/latest
#    excluded them, and the replacement filter has to keep doing so.
cat > "${work}/releases.json" <<'JSON'
[
  {"tag_name": "v9.9.9", "draft": true, "prerelease": false},
  {"tag_name": "v8.8.8", "draft": false, "prerelease": true},
  {"tag_name": "v0.6.0", "draft": false, "prerelease": false}
]
JSON
# ALLOW_BUMP is used here rather than a plain call, because with the refusal in
# place a bump is the only way this case can still observe WHICH tag was picked
# -- and that, not the bump, is what it is testing.
got="$(run_resolver 0.6.0 RELEASE_VERSION_ALLOW_BUMP=1)"
[[ "${got}" == "0.7.0" ]] || fail "expected drafts/prereleases to be skipped and v0.6.0 bumped, got '${got}'"

# 6. A malformed VERSION must stop the run rather than be compared or
#    incremented as a string.
echo "not-a-version" > "${work}/tree/VERSION"
if (
  export PATH="${work}/bin:${PATH}"
  export GH_FIXTURE="${work}/releases.json"
  export GITHUB_REPOSITORY="mrgnhnt96/zonai"
  bash "${work}/tree/tool/ci/resolve_release_version.sh" >/dev/null 2>&1
); then
  fail "resolver accepted a non-semver VERSION"
fi

# 7. DRY RUN: the case that would otherwise refuse is used as-is. This is what
#    lets a Compile be dispatched on a commit that is not a release.
cat > "${work}/releases.json" <<'JSON'
[
  {"tag_name": "v0.8.3", "draft": false, "prerelease": false}
]
JSON
got="$(run_resolver 0.8.3 RELEASE_VERSION_DRY_RUN=1)"
[[ "${got}" == "0.8.3" ]] || fail "dry run should leave VERSION at 0.8.3, got '${got}'"
grep -q 'const kVersion = "0.8.3";' "${work}/tree/apps/zonai/lib/gen/version.dart" \
  || fail "dry run must still write version.dart -- the compile jobs need kVersion"

# 8. A dry run must never INVENT a version either. If it silently bumped, the
#    binaries would carry a version no tag will ever match.
[[ "${got}" != "0.9.0" ]] || fail "dry run bumped the version"

# 9. ...and it must not suppress a legitimate release: with VERSION ahead, the
#    flag changes nothing. A dry run that quietly pinned the old version would
#    make "dry_run left on by accident" ship the wrong kVersion.
got="$(run_resolver 0.8.4 RELEASE_VERSION_DRY_RUN=1)"
[[ "${got}" == "0.8.4" ]] || fail "dry run must honour a VERSION that is ahead, got '${got}'"

# 10. The opt-in bump still works, so reverting the refusal is a decision and
#     not a code edit.
got="$(run_resolver 0.8.3 RELEASE_VERSION_ALLOW_BUMP=1)"
[[ "${got}" == "0.9.0" ]] || fail "RELEASE_VERSION_ALLOW_BUMP did not restore the bump, got '${got}'"

# 11. An unset dispatch input arrives as the EMPTY STRING, not as "false".
#     Treating empty as on would make every Compile a dry run; treating "false"
#     as on would do the same. Both are asserted because GitHub sends one and a
#     human types the other.
if ! err="$(refusal_of 0.8.3 RELEASE_VERSION_DRY_RUN=)"; then
  fail "an empty RELEASE_VERSION_DRY_RUN was treated as enabled"
fi
if ! err="$(refusal_of 0.8.3 RELEASE_VERSION_DRY_RUN=false)"; then
  fail "RELEASE_VERSION_DRY_RUN=false was treated as enabled"
fi
# ...and the string GitHub actually sends for a ticked box does enable it.
got="$(run_resolver 0.8.3 RELEASE_VERSION_DRY_RUN=true)"
[[ "${got}" == "0.8.3" ]] || fail "RELEASE_VERSION_DRY_RUN=true did not enable the dry run"

echo "resolve_release_version.sh: all checks passed"
