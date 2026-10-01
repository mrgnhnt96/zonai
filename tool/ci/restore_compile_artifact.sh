#!/usr/bin/env bash
# Copies an artifact of this commit's Compile run into the checkout, so a Test
# job can reuse what Compile already built instead of building it again.
#
# Usage:
#   restore_compile_artifact.sh <artifact> <destination> [<subdirectory>]
#
# With <subdirectory>, only that part of the artifact is copied -- e.g. the
# `server` half of zonai-gen-sources-<target>, for a job that must not also
# pick up `web`.
#
# Which run: COMPILE_RUN_ID when set (test.yml passes the workflow_run that
# triggered it), otherwise the newest successful Compile for GITHUB_SHA, which
# is how a workflow_dispatch run finds one. A branch usually has none.
#
# Exit 3, and say so, when there is no Compile run to reuse: callers treat that
# as "build it here", not as a failure. Any other non-zero exit is a failure.
#
# Needs GH_TOKEN with `actions: read`, and GITHUB_REPOSITORY / RUNNER_TEMP,
# which every Actions job has.
set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "usage: $0 <artifact> <destination> [<subdirectory>]" >&2
  exit 64
fi
artifact="$1"
destination="$2"
subdirectory="${3:-}"

run_id="${COMPILE_RUN_ID:-}"
if [ -z "${run_id}" ]; then
  run_id="$(gh run list --repo "${GITHUB_REPOSITORY}" \
    --workflow compile.yml --commit "${GITHUB_SHA}" --status success \
    --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
fi
if [ -z "${run_id}" ]; then
  echo "no successful Compile run for ${GITHUB_SHA} -- nothing to reuse"
  exit 3
fi

# Unpacked aside and copied in: `gh run download` refuses to overwrite, and
# some destinations (VERSION) are tracked files.
unpacked="${RUNNER_TEMP}/compile-artifacts/${artifact}"
rm -rf "${unpacked}"
gh run download "${run_id}" --repo "${GITHUB_REPOSITORY}" \
  --name "${artifact}" --dir "${unpacked}"

source_dir="${unpacked}${subdirectory:+/${subdirectory}}"
if [ ! -d "${source_dir}" ]; then
  echo "artifact ${artifact} from Compile run ${run_id} has no ${subdirectory}/" >&2
  exit 1
fi
target="${destination}${subdirectory:+/${subdirectory}}"
mkdir -p "${target}"
cp -R "${source_dir}/." "${target}"
echo "restored ${artifact}${subdirectory:+ (${subdirectory}/)} from Compile run ${run_id} into ${target}"
