#!/usr/bin/env bash
# Provoke check_release_gates.sh into REFUSING, eleven ways.
#
# WHY THE NEGATIVE CONTROLS ARE THE POINT: the artifact that failed here was a
# release gate that had only ever been seen to pass. verify-release.yml is five
# platforms of real work and it was green for months while gating nothing,
# because it ran beside publication instead of before it. A checker never
# observed refusing is indistinguishable from one that cannot refuse -- so the
# positive control (everything green -> exit 0) is one case out of twelve here,
# and the other eleven are all the shapes of "not green" that must stop a
# publish.
#
# `gh` is stubbed the same way tool/ci/test_resolve_release_version.sh stubs it:
# the stub applies the script's REAL `-q` expression to a fixture with jq, so
# the filter under test -- the head_sha select and the newest-run-wins sort,
# which is where a gate like this goes wrong quietly -- is the one that runs.
# The stub deliberately ignores the `head_sha=` query parameter, which is how
# case 8 can prove the filter re-asserts the sha itself rather than trusting the
# server to have filtered.
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to test the release-gate filter" >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="${repo_root}/tool/ci/check_release_gates.sh"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/bin"

cat > "${work}/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stand-in for `gh api <endpoint> -X GET -f ... -q <expr>`: applies the real jq
# expression to the fixture. The `-f` filters are dropped on purpose -- the
# script must not depend on the server having applied them.
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

SHA="1111111111111111111111111111111111111111"
OTHER_SHA="2222222222222222222222222222222222222222"

fail() {
  echo "FAIL: $1" >&2
  [[ -z "${2:-}" ]] || { echo "--- gate output ---" >&2; echo "$2" >&2; }
  exit 1
}

# Writes .workflow_runs from the rows given as `name|status|conclusion|branch|id`.
fixture() {
  local rows=("$@") json="[]" row
  for row in "${rows[@]}"; do
    IFS='|' read -r name status conclusion branch id sha <<<"${row}"
    json="$(jq -c \
      --arg name "${name}" --arg status "${status}" \
      --arg conclusion "${conclusion}" --arg branch "${branch}" \
      --arg sha "${sha:-${SHA}}" --argjson id "${id}" \
      '. + [{name: $name, status: $status, conclusion: $conclusion,
             head_branch: $branch, head_sha: $sha, id: $id}]' <<<"${json}")"
  done
  jq -n --argjson runs "${json}" '{workflow_runs: $runs}' > "${work}/runs.json"
}

# Runs the gate and reports its exit code in `status`, its output in `output`,
# and the job summary it wrote in `summary`.
run_gate() {
  local event="${1}" force="${2}" sha="${3:-${SHA}}" branch="${4:-main}"
  : > "${work}/summary.md"
  set +e
  output="$(
    PATH="${work}/bin:${PATH}" \
    GH_FIXTURE="${work}/runs.json" \
    GITHUB_REPOSITORY="mrgnhnt96/zonai" \
    GITHUB_STEP_SUMMARY="${work}/summary.md" \
    GITHUB_ACTOR="tester" \
    RELEASE_SHA="${sha}" \
    RELEASE_GATE_EVENT="${event}" \
    RELEASE_GATE_BRANCH="${branch}" \
    RELEASE_GATE_FORCE="${force}" \
    bash "${script}" 2>&1
  )"
  status=$?
  set -e
  summary="$(cat "${work}/summary.md")"
}

green_rows=(
  "Test|completed|success|main|100"
  "Verify Release|completed|success|main|101"
)

# 1. POSITIVE CONTROL. Both workflows completed successfully for this exact sha,
#    on the default branch -- the only shape that may publish.
fixture "${green_rows[@]}"
run_gate workflow_run false
[[ "${status}" -eq 0 ]] || fail "refused a commit with both gates green" "${output}"
grep -q "All release gates are green" <<<"${output}" \
  || fail "green run did not say so" "${output}"

# 2. THE REFUSAL THIS LEAF EXISTS FOR: no Test run at all for this commit. Before
#    the gate, dispatching Release here published happily.
fixture "Verify Release|completed|success|main|101"
run_gate workflow_dispatch false
[[ "${status}" -ne 0 ]] || fail "published with NO Test run for the commit" "${output}"
grep -q "Test: no run for ${SHA}" <<<"${output}" \
  || fail "refusal did not name the missing Test run" "${output}"

# 3. A red Test run. Distinct from case 2 -- absent and failed are different
#    bugs, and a gate that only looks for presence passes this one.
fixture "Test|completed|failure|main|100" "Verify Release|completed|success|main|101"
run_gate workflow_dispatch false
[[ "${status}" -ne 0 ]] || fail "published with a FAILED Test run" "${output}"
grep -q "Test: run 100 concluded failure" <<<"${output}" \
  || fail "refusal did not name the failed Test run" "${output}"

# 4. No Verify Release run -- the half that was never actually gating.
fixture "Test|completed|success|main|100"
run_gate workflow_dispatch false
[[ "${status}" -ne 0 ]] || fail "published with NO Verify Release run" "${output}"
grep -q "Verify Release: no run for ${SHA}" <<<"${output}" \
  || fail "refusal did not name the missing Verify Release run" "${output}"

# 5. Still running. `conclusion` is null while a run is in flight, and treating
#    null as "not a failure" is the cheap way to write this check wrongly.
fixture "Test|in_progress||main|100" "Verify Release|completed|success|main|101"
run_gate workflow_dispatch false
[[ "${status}" -ne 0 ]] || fail "published while Test was still in_progress" "${output}"
grep -q "Test: run 100 is in_progress, not completed" <<<"${output}" \
  || fail "refusal did not name the in-flight Test run" "${output}"

# 6. A re-run supersedes what it replaced: red first, green after -> publish.
fixture \
  "Test|completed|failure|main|100" \
  "Test|completed|success|main|102" \
  "Verify Release|completed|success|main|101"
run_gate workflow_dispatch false
[[ "${status}" -eq 0 ]] || fail "a successful re-run of Test did not clear the earlier failure" "${output}"

# 7. And in the other direction, which is the one that matters: green first, red
#    after -> REFUSE. An implementation that scans for "any successful run"
#    passes case 6 and fails here, publishing a commit whose latest verdict is red.
fixture \
  "Test|completed|success|main|100" \
  "Test|completed|failure|main|102" \
  "Verify Release|completed|success|main|101"
run_gate workflow_dispatch false
[[ "${status}" -ne 0 ]] || fail "an older green Test run rescued a newer red one" "${output}"
grep -q "Test: run 102 concluded failure" <<<"${output}" \
  || fail "refusal did not name the newest Test run" "${output}"

# 8. Green runs that belong to a DIFFERENT commit. The stub does not apply the
#    `head_sha=` query parameter, so this is the script's own filter under test
#    -- and "verified some other commit" is precisely how v0.6.3 shipped
#    six-day-old artifacts under a fresh version.
fixture \
  "Test|completed|success|main|100|${OTHER_SHA}" \
  "Verify Release|completed|success|main|101|${OTHER_SHA}"
run_gate workflow_dispatch false
[[ "${status}" -ne 0 ]] || fail "another commit's green runs satisfied the gate" "${output}"
grep -q "Test: no run for ${SHA}" <<<"${output}" \
  || fail "refusal did not treat another commit's run as absent" "${output}"

# 9. Everything green, but the commit is not on the default branch. This gate
#    exists because release.yml's automatic trigger is being turned back on: a
#    Compile dispatched on a feature branch would otherwise walk the whole chain.
fixture \
  "Test|completed|success|feature/x|100" \
  "Verify Release|completed|success|feature/x|101"
run_gate workflow_dispatch false "${SHA}" "feature/x"
[[ "${status}" -ne 0 ]] || fail "published from a non-default branch" "${output}"
grep -q "not the default branch" <<<"${output}" \
  || fail "refusal did not name the branch" "${output}"

# 10. The override works, and LEAVES A TRACE. A force that publishes silently is
#     the same failure as no gate at all, one release later.
fixture "Test|completed|failure|main|100" "Verify Release|completed|success|main|101"
run_gate workflow_dispatch true
[[ "${status}" -eq 0 ]] || fail "force: true did not override a red gate" "${output}"
grep -q "force: true" <<<"${summary}" \
  || fail "the job summary does not record that the release was forced" "${summary}"
grep -q "Test: run 100 concluded failure" <<<"${summary}" \
  || fail "the job summary does not name WHICH gate was skipped" "${summary}"
grep -q "tester" <<<"${summary}" \
  || fail "the job summary does not name who dispatched the forced release" "${summary}"

# 11. Force is not honoured on the automatic path. `workflow_run` carries no
#     inputs, so a `true` arriving there is a stray environment variable rather
#     than a decision -- and an override nobody chose is worse than none.
fixture "Test|completed|failure|main|100" "Verify Release|completed|success|main|101"
run_gate workflow_run true
[[ "${status}" -ne 0 ]] || fail "force was honoured on the automatic workflow_run path" "${output}"

# 12. A sha that is not a full commit sha stops the run. A short or symbolic ref
#     matches no runs, which reads identically to "the gates never ran" -- the
#     right verdict for the wrong reason, and it would mask a real lookup bug.
fixture "${green_rows[@]}"
run_gate workflow_dispatch false "main"
[[ "${status}" -ne 0 ]] || fail "accepted a non-sha as the release commit" "${output}"

# 13. WAITING, not failing. Both Test and Verify Release trigger release.yml, so
#     the first of the two to finish always produces a run whose only complaint
#     is that the other is still going. It must still refuse -- exiting 0 here
#     would publish against a gate that has not answered -- but it must say so
#     as waiting, because this is now the routine case and a routine red that
#     reads as a failure is how a real failure stops being read.
fixture "Test|in_progress||main|100" "Verify Release|completed|success|main|101"
run_gate workflow_run false
[[ "${status}" -ne 0 ]] || fail "published while Test was still in_progress" "${output}"
grep -q "Waiting, not failing" <<<"${output}" \
  || fail "an in-flight gate was reported as a failure rather than as waiting" "${output}"
grep -q "No action needed" <<<"${output}" \
  || fail "the waiting run did not say that no re-run is needed" "${output}"

# 14. The same shape with the OTHER gate in flight, since the two are reached by
#     different branches of the loop and only one of them was written first.
fixture "Test|completed|success|main|100" "Verify Release|queued||main|101"
run_gate workflow_run false
[[ "${status}" -ne 0 ]] || fail "published while Verify Release was still queued" "${output}"
grep -q "Waiting, not failing" <<<"${output}" \
  || fail "a queued Verify Release was reported as a failure rather than as waiting" "${output}"

# 15. A red gate is NOT waiting, even when another gate is also merely in
#     flight. This is the case that decides whether the distinction is real: if
#     "any run not completed" won it, a genuine failure would be dressed up as
#     "no action needed" and left for a trigger that never comes.
fixture "Test|completed|failure|main|100" "Verify Release|in_progress||main|101"
run_gate workflow_run false
[[ "${status}" -ne 0 ]] || fail "published with a FAILED Test run" "${output}"
grep -q "Refusing to publish" <<<"${output}" \
  || fail "a red gate beside an in-flight one was softened into waiting" "${output}"
grep -q "Waiting, not failing" <<<"${output}" \
  && fail "a red gate was reported as waiting" "${output}"

# 16. A missing run is an answer, not a wait. Nothing will trigger this workflow
#     again on behalf of a run that does not exist, so calling it "waiting" would
#     promise a rescue that is never coming.
fixture "Verify Release|completed|success|main|101"
run_gate workflow_run false
[[ "${status}" -ne 0 ]] || fail "published with NO Test run for the commit" "${output}"
grep -q "Waiting, not failing" <<<"${output}" \
  && fail "a missing run was reported as waiting" "${output}"

# 17. On the MANUAL path an in-flight gate is not "waiting" either: a dispatch
#     is not re-triggered by anything, so the person who ran it has to act.
fixture "Test|in_progress||main|100" "Verify Release|completed|success|main|101"
run_gate workflow_dispatch false
[[ "${status}" -ne 0 ]] || fail "published while Test was still in_progress" "${output}"
grep -q "Waiting, not failing" <<<"${output}" \
  && fail "a hand-dispatched run promised an automatic retrigger" "${output}"

echo "check_release_gates.sh: 17 checks passed (16 of them refusals)"
