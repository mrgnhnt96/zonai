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
import sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required to check workflow syntax")

paths = sorted(glob.glob(".github/workflows/*.yml"))
if not paths:
    sys.exit(".github/workflows/*.yml matched nothing -- did the path move?")

failed = False
documents = {}
for path in paths:
    try:
        document = yaml.safe_load(open(path))
    except yaml.YAMLError as error:
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
    # byte bindings, which apps/zonai/lib/gen/ needs and a checkout lacks.
    ".github/workflows/release.yml",
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
    elif GATE_SCRIPT not in yaml.dump(gate):
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

sys.exit(1 if failed else 0)
PY
