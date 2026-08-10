#!/usr/bin/env bash
# Parse every workflow so a YAML mistake fails here rather than on push, where
# GitHub reports it as a run that never starts.
#
# This is a syntax gate, not a behaviour one: it cannot tell whether a job does
# what it claims. The real exercise of these workflows is running them.
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

sys.exit(1 if failed else 0)
PY
