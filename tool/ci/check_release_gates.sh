#!/usr/bin/env bash
# Refuse to publish unless the workflows that prove THIS EXACT COMMIT are green.
#
# THE BUG THIS EXISTS FOR, measured 2026-08-14 on eea8e74: verify-release.yml
# was its own workflow triggered by `workflow_run: [Compile] completed`, and
# release.yml's `workflow_run: [Verify Release]` trigger was commented out,
# leaving `workflow_dispatch:` as its only door. So verification ran BESIDE
# publication rather than before it, and nothing at all stopped a human
# dispatching Release while Verify Release was red, still running, or had never
# run for that commit. The verify matrix is good work -- five platforms, `zonai
# build` on each, a cross-target build/run pair, an upgrade compat check. It
# simply was not a gate. See docs/testing-strategy.md Step 5.
#
# WHY IT QUERIES RUNS BY head_sha RATHER THAN TRUSTING THE TRIGGER: `workflow_run`
# ordering is what produced the bug. "Verify Release finished" says nothing about
# WHICH commit it verified, and release.yml has already shipped one commit's
# version with another commit's artifacts once (v0.6.3, from six-day-old compile
# artifacts). The only question worth asking is "is there a completed, successful
# run of this workflow whose head_sha is the commit I am about to publish", and
# that is a lookup, not an inference.
#
# WHAT IT CHECKS, all three overridable only by an explicit force on the manual
# path (see below):
#   Test            -- the suite, AND the five-platform artifact verification:
#                      verify-release.yml is a reusable workflow that test.yml
#                      calls (its `verify-release` job), so one green Test run
#                      covers both. It used to be a second required workflow
#                      here; the two were merged because two prerequisites and
#                      one `workflow_run` trigger meant release.yml had to fire
#                      on both and refuse the loser, one red run per release.
#                      Test has NO `push` trigger: test.yml runs on
#                      `pull_request`, on `workflow_run: [Compile] completed`,
#                      and on `workflow_dispatch`. So a commit pushed to main
#                      has no Test run until something compiles it, and what
#                      makes the release chain satisfy this gate is that
#                      dispatching Compile produces one at the same head_sha.
#   branch          -- the commit is on the default branch. This one is here
#                      because turning the automatic trigger back on means a
#                      Compile dispatched on a feature branch would otherwise
#                      walk the whole chain and publish from it.
#
# WHAT MERGING THE TWO COST, out loud: this file can no longer tell that the
# verification ran at all. A green Test run satisfies it whether or not
# test.yml still calls verify-release.yml, and deleting that one job would be
# invisible here. tool/ci/check_workflows.sh asserts the call exists, which is
# the only thing standing between that deletion and a release nobody verified.
#
# THE ONE REFUSAL THAT WILL LOOK LIKE A BUG AND IS NOT: release.yml's own
# "Commit release version" step pushes VERSION with GITHUB_TOKEN, and GitHub
# deliberately starts no workflow runs from those pushes -- so the `chore:
# release vX` commit at the head of main has NO Test run, and a release
# dispatched on it with nothing pushed since is correctly refused. Push the next
# commit, or re-run Test on that sha. Refusing is the right answer: nothing has
# tested that commit.
#
# WHAT IT CANNOT CHECK, out loud: whether a green Test run MEANT anything -- a
# workflow whose jobs are all `continue-on-error` concludes success and this
# believes it. It also cannot see a check that was never wired: only the
# workflow named here is required, and a second suite added later is invisible
# until somebody adds it to REQUIRED_WORKFLOWS. And it reads the newest 100 runs
# for the commit (see the query below), so a commit re-run more than 100 times
# would be judged on a truncated list.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
sha="${RELEASE_SHA:-}"
event="${RELEASE_GATE_EVENT:-}"
branch="${RELEASE_GATE_BRANCH:-}"
default_branch="${RELEASE_GATE_DEFAULT_BRANCH:-main}"
force="${RELEASE_GATE_FORCE:-false}"

REQUIRED_WORKFLOWS=("Test")

# Hex-validated before it is interpolated into the jq filter below, and because
# a truncated or symbolic ref here would silently match no runs -- which reads
# identically to "the gates never ran" and would be refused for the wrong reason.
if [[ ! "${sha}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "RELEASE_SHA must be a full 40-character commit sha, got '${sha}'" >&2
  exit 1
fi

emit() {
  echo "$1"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    echo "$1" >> "${GITHUB_STEP_SUMMARY}"
  fi
}

# One API call, and the filter is the load-bearing part: it re-asserts head_sha
# itself rather than trusting the `head_sha=` query parameter, and orders
# newest-first by id so a re-run supersedes the attempt it replaced. Ordering
# matters in BOTH directions -- a later red run must bury an earlier green one
# just as much as the reverse. Page one only: the API returns runs newest-first,
# so this is the newest 100 runs for this commit.
runs="$(
  gh api -X GET "repos/${repo}/actions/runs" \
    -f head_sha="${sha}" \
    -f per_page=100 \
    -q "[.workflow_runs[]? | select(.head_sha == \"${sha}\")]
        | sort_by(.id) | reverse | .[]
        | [.name, .status, (.conclusion // \"\"), (.head_branch // \"\"), (.id|tostring)]
        | @tsv"
)"

# Newline-separated rather than an array: bash 3.2 (macOS, and what
# check_shell_syntax.sh parses with) errors on `"${empty[@]}"` under `set -u`,
# and "no gate failed" is the common case.
refusals=""
note_refusal() { refusals="${refusals}${1}"$'\n'; }

# Tracks whether EVERY refusal is "that gate has not finished yet" rather than
# "that gate said no". The two are the same exit code and must stay that way --
# publishing on an unfinished gate is the whole thing this script exists to stop
# -- but they are not the same event, and reading them as one is expensive in
# both directions: a waiting run treated as a failure sends somebody debugging a
# release that is fine, and once waiting runs are known to be routine, a real
# red one gets waved past as "just the usual".
#
# This used to be the COMMON case, and that was the bug worth fixing rather than
# labelling: release.yml fired on both Test and Verify Release, so the first to
# finish always produced one of these and every release carried a red run that
# meant nothing. With one prerequisite workflow, a wait on the automatic path
# now takes something unusual -- Test re-run and back in flight by the time this
# job reaches the API. Rare, still possible, and still refused.
only_waiting=true

emit "## Release gate for \`${sha}\`"
emit ""
emit "| gate | verdict |"
emit "| --- | --- |"

for workflow in "${REQUIRED_WORKFLOWS[@]}"; do
  # Already newest-first, so the first matching row is the run that counts.
  row="$(awk -F'\t' -v want="${workflow}" '$1 == want { print; exit }' <<<"${runs}")"

  if [[ -z "${row}" ]]; then
    emit "| ${workflow} | **NO RUN for this commit** |"
    note_refusal "${workflow}: no run for ${sha}"
    only_waiting=false
    continue
  fi

  status="$(cut -f2 <<<"${row}")"
  conclusion="$(cut -f3 <<<"${row}")"
  run_id="$(cut -f5 <<<"${row}")"
  run_url="https://github.com/${repo}/actions/runs/${run_id}"

  if [[ "${status}" != "completed" ]]; then
    emit "| ${workflow} | **${status}** ([run ${run_id}](${run_url})) |"
    note_refusal "${workflow}: run ${run_id} is ${status}, not completed"
  elif [[ "${conclusion}" != "success" ]]; then
    emit "| ${workflow} | **${conclusion}** ([run ${run_id}](${run_url})) |"
    note_refusal "${workflow}: run ${run_id} concluded ${conclusion}"
    only_waiting=false
  else
    emit "| ${workflow} | success ([run ${run_id}](${run_url})) |"
  fi
done

if [[ -z "${branch}" ]]; then
  emit "| branch | **unknown** |"
  note_refusal "branch: could not determine which branch ${sha} is being released from"
  only_waiting=false
elif [[ "${branch}" != "${default_branch}" ]]; then
  emit "| branch | **${branch}**, expected ${default_branch} |"
  note_refusal "branch: releasing from '${branch}', not the default branch '${default_branch}'"
  only_waiting=false
else
  emit "| branch | ${branch} |"
fi

emit ""

if [[ -z "${refusals}" ]]; then
  if [[ "${force}" == "true" ]]; then
    emit "\`force: true\` was requested, but every gate is green -- nothing was skipped."
  fi
  emit "All release gates are green for this commit."
  exit 0
fi

# `force` is honoured ONLY on the hand-dispatched path. The automatic
# `workflow_run` trigger carries no inputs, so anything setting this there is a
# stray environment variable rather than a decision somebody made, and an
# override nobody chose is worse than no override.
if [[ "${force}" == "true" && "${event}" == "workflow_dispatch" ]]; then
  emit "> [!CAUTION]"
  emit "> **This release was published with \`force: true\`, past gates that were not green.**"
  emit ">"
  emit "> Skipped:"
  while IFS= read -r refusal; do
    [[ -n "${refusal}" ]] || continue
    emit "> - ${refusal}"
  done <<<"${refusals}"
  emit ">"
  emit "> Dispatched by: ${GITHUB_ACTOR:-unknown}"
  exit 0
fi

if [[ "${only_waiting}" == "true" && "${event}" == "workflow_run" ]]; then
  emit "> [!NOTE]"
  emit "> **Waiting, not failing.** Nothing is wrong with \`${sha}\`; a gate has"
  emit "> simply not finished yet:"
  while IFS= read -r refusal; do
    [[ -n "${refusal}" ]] || continue
    emit "> - ${refusal}"
  done <<<"${refusals}"
  emit ">"
  emit "> **Probably no action needed.** Test triggers this workflow when it"
  emit "> completes, so the run above will start a fresh attempt on its own"
  emit "> when it finishes, and that attempt is the one that publishes. Wait"
  emit "> for it rather than re-running this run."
  emit ">"
  emit "> Reaching here at all is unusual now that Test is the only gate -- it"
  emit "> means the run that fired this one is already back in flight, which"
  emit "> normally means somebody re-ran it. If it finishes green and no"
  emit "> Release attempt follows, dispatch Release by hand."
  emit ">"
  emit "> This run still fails, on purpose: exiting 0 here would let every job"
  emit "> below it publish against a gate that has not answered."
  exit 1
fi

emit "> [!IMPORTANT]"
emit "> **Refusing to publish.** These gates are not green for \`${sha}\`:"
while IFS= read -r refusal; do
  [[ -n "${refusal}" ]] || continue
  emit "> - ${refusal}"
done <<<"${refusals}"
emit ">"
if [[ "${event}" == "workflow_dispatch" ]]; then
  emit "> Run the missing workflows on this ref, or re-dispatch with \`force: true\`"
  emit "> to publish anyway -- which records the skip above."
else
  emit "> \`force\` is not available on the automatic path; dispatch Release by hand"
  emit "> if this needs to ship regardless."
fi

exit 1
