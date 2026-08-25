#!/usr/bin/env bash
# One portability trap, encoded because it cost a release chain three platforms.
#
# `mktemp -t PREFIX` means two different things:
#   * BSD/macOS  -- PREFIX is a prefix; mktemp appends its own random suffix.
#   * GNU/Linux  -- PREFIX is a TEMPLATE, and one without at least three
#                   trailing X's is refused: "mktemp: too few X's in template".
#
# Every dev machine here is macOS and every runner but two is not, so the
# spelling that works locally is exactly the one that fails in CI -- and it
# fails by assigning an EMPTY path, which downstream code then passes to `tee`
# and `grep` as an empty filename. tool/ci/web_build.sh did this: the jaspr
# build succeeded, `tee ""` failed, pipefail turned that into a non-zero
# pipeline, and the wrapper reported "web build: FAILED" over a build that had
# just printed "Completed building project". Compile 32795339596 lost
# linux-x64, linux-arm64 and windows-x64 to it while both macOS legs stayed
# green -- the shape of failure that is hardest to read, because the platforms
# that disagree are the ones nobody can reproduce on.
#
# The portable spelling is a positional template: mktemp "${TMPDIR:-/tmp}/x.XXXXXX"
#
# Scope is a grep, deliberately: this asks one lexical question of every tracked
# shell source, including the shell embedded in scripts.yaml and the workflows.
# It cannot see a template built from a variable, and says so below.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

# A template argument is fine only when it ends in three or more X's.
pattern='mktemp[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*-t[[:space:]]+[^[:space:];|&)]*'

scan() {
  # $@ = files. Prints offending "file:line:text" lines.
  #
  # Comment lines are skipped: this very file, and web_build.sh's fix, both
  # SPELL the bad form in prose to explain it, and a check that fails on its
  # own explanation teaches people to delete the explanation.
  grep -nE "${pattern}" "$@" 2>/dev/null | while IFS= read -r hit; do
    text=$(printf '%s' "$hit" | sed -E 's/^[^:]*:[0-9]+://')
    case "$(printf '%s' "$text" | sed -E 's/^[[:space:]]*//')" in
      \#*) continue ;;
    esac
    arg=$(printf '%s' "$hit" | sed -E "s/.*-t[[:space:]]+//; s/[[:space:]].*//; s/[\"']//g")
    case "$arg" in
      *XXX*) ;;
      *) printf '%s\n' "$hit" ;;
    esac
  done
}

# A `while read` rather than `mapfile`: macOS ships bash 3.2, which has no
# mapfile, and this must run for a contributor as well as on a runner.
sources=()
while IFS= read -r src; do
  sources+=("$src")
done < <(git ls-files '*.sh' 'scripts.yaml' '.github/workflows/*.yml')

if [ "${#sources[@]}" -eq 0 ]; then
  echo "check_shell_portability: found no shell sources to scan -- did the" >&2
  echo "  repo layout change? A silent pass over nothing is not a pass." >&2
  exit 1
fi

offenders="$(scan "${sources[@]}" || true)"

# Positive control. Silence above proves nothing unless the same scan still
# catches a known-bad line, so feed it one.
control_dir="$(mktemp -d "${TMPDIR:-/tmp}/zonai_portability.XXXXXX")"
trap 'rm -rf "${control_dir}"' EXIT
printf 'log="$(mktemp -t zonai_web_build)"\n' > "${control_dir}/bad.sh"
printf 'log="$(mktemp "${TMPDIR:-/tmp}/ok.XXXXXX")"\n' >> "${control_dir}/bad.sh"
control="$(scan "${control_dir}/bad.sh" || true)"
if [ -z "${control}" ]; then
  echo "check_shell_portability: the positive control was NOT caught, so this" >&2
  echo "  check is blind and its silence over the repo means nothing." >&2
  exit 1
fi
if [ "$(printf '%s\n' "${control}" | wc -l | tr -d ' ')" != "1" ]; then
  echo "check_shell_portability: the control caught the portable spelling too --" >&2
  echo "  this check would fail correct code. Fix the pattern." >&2
  printf '%s\n' "${control}" >&2
  exit 1
fi

if [ -n "${offenders}" ]; then
  echo "check_shell_portability: \`mktemp -t\` with a template that has no X's." >&2
  echo "  GNU coreutils refuses it and assigns an EMPTY path; macOS accepts it," >&2
  echo "  so this passes locally and fails on every Linux and Windows runner." >&2
  echo "  Use a positional template instead: mktemp \"\${TMPDIR:-/tmp}/name.XXXXXX\"" >&2
  echo >&2
  printf '%s\n' "${offenders}" >&2
  exit 1
fi

echo "ok: no BSD-only \`mktemp -t\` templates (scanned ${#sources[@]} shell source(s); control caught)"
echo "    NOT checked: a template built from a variable, one reached through \$(...),"
echo "    or a bad spelling that only ever appears inside a comment."
