#!/usr/bin/env bash
# Parse every workflow so a YAML mistake fails here rather than on push, where
# GitHub reports it as a run that never starts.
#
# Mostly a syntax gate: it cannot tell whether a job does what it claims, and
# the real exercise of these workflows is running them. The one behavioural
# thing it does check is a name two workflows have to agree on, because that
# particular disagreement produces no error at all -- see below.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

python3 - <<'PY'
import glob
import json
import subprocess
import sys

# PyYAML if present, otherwise Ruby's Psych via a JSON bridge. Neither is
# guaranteed on a developer machine, and for a long stretch on at least one of
# them PyYAML was absent -- so this script exited 1 before checking anything,
# every time. A gate that cannot run is not a strict gate; it is a blind one
# that also blocks the commit, which is how it came to be pinned as a known
# environmental failure and routed around. Two parsers is the fix.
#
# Ruby's Psych is a YAML 1.1 parser exactly like PyYAML, so a bare `on:` key
# arrives as the BOOLEAN True there too, and JSON cannot carry a boolean key.
# The bridge maps it back to the string "on"; the readers below still accept
# both, because under PyYAML it is still True.
_RUBY_BRIDGE = (
    "require 'yaml'; require 'json'; "
    "d = YAML.load_file(ARGV[0]); "
    "d = d.transform_keys { |k| k == true ? 'on' : k } if d.is_a?(Hash); "
    "print JSON.generate(d)"
)

try:
    import yaml
except ImportError:
    yaml = None


def _have_ruby():
    try:
        subprocess.run(["ruby", "-e", ""], capture_output=True, check=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


_RUBY = _have_ruby() if yaml is None else False
if yaml is None and not _RUBY:
    sys.exit(
        "no YAML parser: install PyYAML (pip install PyYAML) or Ruby. "
        "Refusing to report a pass without parsing anything."
    )
print(f"  parser: {'PyYAML' if yaml else 'ruby/psych via JSON'}")


class ParseError(Exception):
    pass


def load_workflow(path):
    if yaml is not None:
        try:
            return yaml.safe_load(open(path))
        except yaml.YAMLError as error:
            raise ParseError(error) from error
    proc = subprocess.run(
        ["ruby", "-e", _RUBY_BRIDGE, path], capture_output=True, text=True
    )
    if proc.returncode != 0:
        # FIRST stderr line: that is Psych's message. The last line is a
        # backtrace frame, which names this bridge instead of the mistake.
        lines = [l for l in proc.stderr.splitlines() if l.strip()]
        raise ParseError(lines[0].strip() if lines else "ruby failed to parse")
    return json.loads(proc.stdout)


def to_text(obj):
    """Flatten a job for substring searching. Only ever used for `in` checks."""
    return json.dumps(obj, default=str, sort_keys=True)

paths = sorted(glob.glob(".github/workflows/*.yml"))
if not paths:
    sys.exit(".github/workflows/*.yml matched nothing -- did the path move?")

failed = False
documents = {}
for path in paths:
    try:
        document = load_workflow(path)
    except ParseError as error:
        print(f"{path}: {error}")
        failed = True
        continue

    if not isinstance(document, dict) or "jobs" not in document:
        print(f"{path}: parsed but has no `jobs` mapping")
        failed = True
        continue

    print(f"  ok: {path} ({len(document['jobs'])} job(s))")
    documents[path] = document

# native-libs.yml publishes the prebuilt libraries to a rolling release;
# compile.yml pulls them back out of it by tag. Nothing connects the two but
# this string, and getting it wrong is SILENT: `gh release download` fails, the
# step is continue-on-error by design (a missing cache must not fail a compile),
# and every run from then on rebuilds libsodium from source while reporting
# success. Slower forever, with nothing pointing at why.
tags = {
    path: (document.get("env") or {}).get("NATIVE_LIBS_CACHE_TAG")
    for path, document in documents.items()
}
declared = {path: tag for path, tag in tags.items() if tag}

expected = {
    ".github/workflows/compile.yml",
    ".github/workflows/native-libs.yml",
    # cross-target-build restores the same libraries to generate the native
    # byte bindings, which apps/zonai/lib/gen/ needs and a checkout lacks. It
    # was release.yml's declaration until that job moved out of the release
    # into its own workflow.
    ".github/workflows/post-release-verify.yml",
    # test.yml's unit/cli/e2e jobs run `bootstrap test`, which is resqlite.gen
    # and argon2.gen -- the same compile-libsodium-from-source cost compile.yml
    # restores this cache to avoid, now paid on three platforms per push
    # instead of once per release.
    ".github/workflows/test.yml",
}
if set(declared) != expected:
    print(
        "NATIVE_LIBS_CACHE_TAG should be declared by exactly "
        f"{sorted(expected)}, found {sorted(declared)}. If the cache moved, "
        "update this check with it."
    )
    failed = True
elif len(set(declared.values())) != 1:
    print(f"NATIVE_LIBS_CACHE_TAG disagrees between workflows: {declared}")
    failed = True
else:
    print(f"  ok: NATIVE_LIBS_CACHE_TAG agrees ({next(iter(set(declared.values())))})")


# The release ordering invariant. tool/ci/check_release_gates.sh can refuse --
# its own suite provokes eleven refusals -- but a refusal only stops a release
# if every publishing job is DOWNSTREAM of it. That wiring lives in YAML, cannot
# be unit-tested, and has exactly the shape that rots: someone adds a job and
# forgets `needs:`, or adds `always()` to an `if:` to make a run finish, and the
# gate is still there, still green, still gating nothing. Which is precisely the
# state this file was found in: verify-release.yml ran BESIDE publication for
# months because release.yml's `workflow_run: [Verify Release]` trigger was
# commented out. See docs/testing-strategy.md Step 5.
RELEASE = ".github/workflows/release.yml"
GATE_JOB = "release-gate"
GATE_SCRIPT = "tool/ci/check_release_gates.sh"

release = documents.get(RELEASE)
if release is None:
    print(f"{RELEASE} did not parse, so its release gate could not be checked")
    failed = True
else:
    # PyYAML is a YAML 1.1 parser, where the bare key `on` is the BOOLEAN True.
    # Reading `document["on"]` here finds nothing and would silently skip every
    # trigger check below -- a check that cannot fail, on the file whose
    # triggers are the bug.
    triggers = release.get("on", release.get(True)) or {}
    jobs = release.get("jobs") or {}

    dispatch = triggers.get("workflow_dispatch") or {}
    run_trigger = triggers.get("workflow_run") or {}

    if "Verify Release" not in (run_trigger.get("workflows") or []):
        print(
            f"{RELEASE}: `on.workflow_run.workflows` must include 'Verify Release'. "
            "Without it, workflow_dispatch is the only door and verification "
            "runs beside publication instead of before it."
        )
        failed = True

    # Both gates, or the release needs a human again. Compile fans Test and
    # Verify Release out in parallel and Verify Release always finishes first,
    # so with only Verify Release listed the trigger fires while Test is still
    # running, the gate refuses, and nothing ever fires again -- publishing then
    # depends on somebody noticing Test go green and re-running the failed run
    # by hand. Dropping 'Test' from this list does not fail anything; it just
    # quietly reinstates that hand step, which is why it is asserted here.
    if "Test" not in (run_trigger.get("workflows") or []):
        print(
            f"{RELEASE}: `on.workflow_run.workflows` must include 'Test'. "
            "Without it, whichever gate finishes last does not trigger the "
            "release, and a green chain waits for a human to re-run it."
        )
        failed = True

    # Without this, listing Test above turns every owner PR into a refused
    # Release run, because test.yml runs on `pull_request` too.
    if (run_trigger.get("branches") or []) != ["main"]:
        print(
            f"{RELEASE}: `on.workflow_run.branches` must be ['main']. "
            "test.yml runs on pull_request, so an unfiltered trigger fires a "
            "Release attempt for every PR."
        )
        failed = True

    if "force" not in ((dispatch.get("inputs") or {})):
        print(
            f"{RELEASE}: `workflow_dispatch` must declare a `force` input -- it is "
            "the only way past the gate, and it has to be a deliberate, recorded one."
        )
        failed = True

    gate = jobs.get(GATE_JOB)
    if gate is None:
        print(f"{RELEASE}: no `{GATE_JOB}` job")
        failed = True
    elif GATE_SCRIPT not in to_text(gate):
        print(f"{RELEASE}: `{GATE_JOB}` does not run {GATE_SCRIPT}")
        failed = True

    def needs_of(name):
        declared_needs = (jobs.get(name) or {}).get("needs") or []
        return [declared_needs] if isinstance(declared_needs, str) else declared_needs

    def reaches_gate(name, seen=None):
        seen = seen or set()
        if name in seen:
            return False
        seen.add(name)
        parents = needs_of(name)
        return GATE_JOB in parents or any(reaches_gate(p, seen) for p in parents)

    for name, job in jobs.items():
        if name == GATE_JOB:
            continue
        if not reaches_gate(name):
            print(
                f"{RELEASE}: job `{name}` does not depend on `{GATE_JOB}`, directly "
                "or through another job -- it would publish while the gate refuses."
            )
            failed = True
        # A status function in an `if:` is what detaches a job from its needs'
        # verdict: `always()` runs it even when the gate failed. Nothing in this
        # file needs one, and one added here would reopen the door silently.
        condition = str(job.get("if", ""))
        for bypass in ("always(", "cancelled("):
            if bypass in condition:
                print(
                    f"{RELEASE}: job `{name}` uses `{bypass})` in its `if:`, which "
                    f"makes it run even when `{GATE_JOB}` refuses."
                )
                failed = True

    if not failed:
        print(f"  ok: every release.yml job is gated behind `{GATE_JOB}`")


# The post-release half of the cross-target gate. It used to be two jobs in
# release.yml with `needs: release`; it is now its own workflow, so a failure
# there no longer reddens a Release run that published correctly. What that
# split costs is a connection nothing but a string enforces: if this trigger is
# dropped, or the Release workflow is renamed, the check does not fail -- it
# stops running, and a release stops being verified against the artifact people
# actually download. Exactly the shape of the bug that motivated the release
# gate above, so it gets the same treatment.
POST_RELEASE = ".github/workflows/post-release-verify.yml"
POST_RELEASE_JOBS = {"cross-target-build", "cross-target-run"}

post_release = documents.get(POST_RELEASE)
if post_release is None:
    print(
        f"{POST_RELEASE} is missing or did not parse. It carries the "
        "post-release cross-target check that release.yml no longer runs; "
        "without it nothing verifies a released bundle's native libraries."
    )
    failed = True
else:
    # `on` is the YAML 1.1 boolean True -- same trap as release.yml above.
    triggers = post_release.get("on", post_release.get(True)) or {}
    run_trigger = triggers.get("workflow_run") or {}

    if "Release" not in (run_trigger.get("workflows") or []):
        print(
            f"{POST_RELEASE}: `on.workflow_run.workflows` must include "
            "'Release'. Without it this workflow never fires on its own and "
            "the post-release check silently stops happening."
        )
        failed = True

    if (run_trigger.get("branches") or []) != ["main"]:
        print(
            f"{POST_RELEASE}: `on.workflow_run.branches` must be ['main'], "
            "matching release.yml -- a Release dispatched from a side branch "
            "must not drag a verification of main behind it."
        )
        failed = True

    # The re-run door. This runs after publication by construction, so the
    # answer to a failure is "fix it and check again", and without a dispatch
    # trigger the only way to check again is to cut another release.
    if "workflow_dispatch" not in triggers:
        print(
            f"{POST_RELEASE}: must keep a `workflow_dispatch` trigger -- it is "
            "the only way to re-check a release after a fix without cutting a "
            "new one, and the fallback if the workflow_run chain stops firing."
        )
        failed = True

    missing_jobs = POST_RELEASE_JOBS - set(post_release.get("jobs") or {})
    if missing_jobs:
        print(
            f"{POST_RELEASE}: missing job(s) {sorted(missing_jobs)}. Both "
            "halves are needed: one builds the bundle on macOS, the other is "
            "the only thing that runs it on Linux."
        )
        failed = True

    if not failed:
        print("  ok: post-release-verify.yml is fired by Release and dispatchable")


# What FEEDS the gate, and why prose about it needs a check under it.
#
# check_release_gates.sh demands a green Test and Verify Release run for the
# exact sha. Neither has a `push` trigger: both hang off `workflow_run:
# [Compile]`, so dispatching Compile is what produces both verdicts at that sha
# and lets the chain satisfy its own gate. Remove that trigger and every release
# refuses -- loud, but from a message that names the gate rather than the wiring.
#
# The `push` half is here because the prose rotted once already: that script
# claimed "Test runs on push to main, so a main commit has one", which was true
# when written and false after the trigger was dropped, and it sent a reader
# hunting for a run nothing creates. Adding a `push:` trigger back to test.yml is
# a legitimate change -- this check is not a prohibition. It exists so that the
# comment gets updated in the same commit rather than becoming wrong again.
FED_BY_COMPILE = {
    ".github/workflows/test.yml": "Test",
    ".github/workflows/verify-release.yml": "Verify Release",
}

for path, display in FED_BY_COMPILE.items():
    document = documents.get(path)
    if document is None:
        print(f"{path} did not parse, so its triggers could not be checked")
        failed = True
        continue

    # `on` is the YAML 1.1 boolean True -- same trap as release.yml above.
    triggers = document.get("on", document.get(True)) or {}
    workflows = ((triggers.get("workflow_run") or {}).get("workflows")) or []

    if "Compile" not in workflows:
        print(
            f"{path}: `on.workflow_run.workflows` must include 'Compile'. "
            f"{GATE_SCRIPT} requires a green {display} run for the released "
            "sha, and Compile is what produces one -- without this trigger "
            "every release refuses at the gate."
        )
        failed = True

    if "push" in triggers:
        print(
            f"{path}: a `push` trigger was added. That is allowed, but "
            f"{GATE_SCRIPT}'s header says {display} has none and explains the "
            "release chain in those terms -- update that comment in this "
            "commit, then update this check."
        )
        failed = True

if not failed:
    print("  ok: Test and Verify Release are fed by Compile, and neither on push")

sys.exit(1 if failed else 0)
PY
