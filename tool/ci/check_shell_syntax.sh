#!/usr/bin/env bash
# Parse the shell embedded in scripts.yaml and the workflow `run:` blocks.
#
# check_workflows.sh proves the YAML parses. That says nothing about the shell
# *inside* it, which is where the real logic lives: `resqlite.gen` alone carries
# arrays, subshells and conditionals, and a typo there surfaces as a compile job
# failing minutes in, on one platform, in a log nobody reads until a release is
# blocked.
#
# This is a syntax gate, not a behaviour one -- `bash -n` proves a block parses,
# never that it does the right thing. The blocks are also checked with the local
# bash, which on macOS is 3.2 while CI runs 5.x; that direction is the safe one
# (3.2 accepts a subset), but a 5.x-only construct would pass CI and fail here.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${repo_root}"

python3 - <<'PY'
import glob
import re
import subprocess
import sys
import tempfile
import os

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required to check shell syntax")

# `${{ ... }}` is GitHub Actions / sip interpolation and is not valid bash --
# `${{` is a malformed parameter expansion. Replace each with a plain word so
# the surrounding structure still gets parsed.
EXPRESSION = re.compile(r"\$\{\{[^{}]*\}\}")

checked = 0
failed = False


def check(label, script):
    global checked, failed
    if "\n" not in script:
        # Single-line entries are `cd x && dart run y` -- nothing to get wrong
        # that `bash -n` would catch, and there are hundreds of them.
        return
    checked += 1
    with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as handle:
        handle.write(EXPRESSION.sub("EXPR", script))
        path = handle.name
    try:
        result = subprocess.run(
            ["bash", "-n", path], capture_output=True, text=True
        )
    finally:
        os.unlink(path)
    if result.returncode != 0:
        print(f"  FAIL: {label}\n{result.stderr.strip()}")
        failed = True
    else:
        print(f"  ok: {label}")


def walk_scripts(node, trail):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "(command)":
                entries = value if isinstance(value, list) else [value]
                for index, entry in enumerate(entries):
                    if isinstance(entry, str):
                        check(f"scripts.yaml {'.'.join(trail)}[{index}]", entry)
            elif not key.startswith("("):
                walk_scripts(value, trail + [str(key)])


walk_scripts(yaml.safe_load(open("scripts.yaml")), [])

for path in sorted(glob.glob(".github/workflows/*.yml")):
    document = yaml.safe_load(open(path))
    for job_name, job in (document.get("jobs") or {}).items():
        for index, step in enumerate(job.get("steps") or []):
            if not isinstance(step, dict) or "run" not in step:
                continue
            # A step inherits `defaults.run.shell` when it sets none; every
            # inherited case in this repo is bash, and pwsh steps say so.
            shell = step.get("shell", "bash")
            if shell not in ("bash", "sh"):
                continue
            label = f"{path} {job_name}[{index}] {step.get('name', '')}".strip()
            check(label, step["run"])

# A refactor that renamed `(command)` or restructured `jobs` would otherwise
# leave this reporting success having parsed nothing at all.
if checked == 0:
    sys.exit("Found no multi-line shell blocks -- did scripts.yaml or the "
             "workflow layout change shape?")

print(f"Checked {checked} shell block(s).")
sys.exit(1 if failed else 0)
PY
