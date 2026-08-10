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

run_resolver() {
  local repo_version="$1"
  echo "${repo_version}" > "${work}/tree/VERSION"
  (
    export PATH="${work}/bin:${PATH}"
    export GH_FIXTURE="${work}/releases.json"
    export GITHUB_REPOSITORY="mrgnhnt96/zonai"
    unset GITHUB_OUTPUT
    bash "${work}/tree/tool/ci/resolve_release_version.sh" >/dev/null
  )
  tr -d '[:space:]' < "${work}/tree/VERSION"
}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# 1. A patch bump ahead of the latest CLI release is honoured -- and must not be
#    dragged to some package release's tag.
got="$(run_resolver 0.6.1)"
[[ "${got}" == "0.6.1" ]] || fail "expected 0.6.1 from a repo version ahead of v0.6.0, got '${got}'"

# 2. The regression itself: a repo version at or behind the latest CLI release
#    bumps the CLI's minor. Before the fix this produced zonai_schema-v0.2.0,
#    because the package release was the one being bumped.
got="$(run_resolver 0.6.0)"
[[ "${got}" == "0.7.0" ]] || fail "expected 0.7.0 (minor bump of v0.6.0), got '${got}'"
[[ "${got}" != *zonai_* ]] || fail "resolved a package release tag as the CLI version: '${got}'"

# 3. kVersion has to follow VERSION, since the two are compared at runtime.
grep -q 'const kVersion = "0.7.0";' "${work}/tree/apps/zonai/lib/gen/version.dart" \
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
got="$(run_resolver 0.6.0)"
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

echo "resolve_release_version.sh: all checks passed"
