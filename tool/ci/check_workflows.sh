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

expected = {".github/workflows/compile.yml", ".github/workflows/native-libs.yml"}
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

sys.exit(1 if failed else 0)
PY
