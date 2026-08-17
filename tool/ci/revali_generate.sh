#!/usr/bin/env bash
# Runs revali's server codegen, retrying ONLY the one failure that is known to
# be a lost race rather than a broken tree.
#
# THE FAILURE. revali builds its analyzer with `resourceProvider: _memoryProvider`
# (packages/revali/lib/ast/analyzer/analyzer.dart, `_createVirtualWorkspace`), so
# the entire Dart SDK plus the workspace is mirrored into a MemoryResourceProvider
# first. Every read is queued into ONE unbounded `Future.wait`, and each is
# wrapped in `catch (_) { return (file, null); }` while the collector only writes
# `if (bytes != null)`. A read that failed under file-handle pressure is therefore
# byte-identical to a file that was never there, and it surfaces thousands of
# lines later as:
#
#   Error initializing analyzer
#   FileSystemException(path=...\dart\<ver>\x64\version; message=File does not exist.)
#   package:analyzer/src/dart/sdk/sdk.dart  FolderBasedDartSdk.languageVersion
#
# Nothing about it is Windows-specific; Linux and macOS just have far higher
# handle limits. It is pressure-sensitive, so it got worse when the OAuth
# campaign added several hundred workspace files that now compete with the SDK
# reads in that same `Future.wait` -- every windows leg of `Test` was green at
# v0.7.2 and `unit`/`cli` failed five times running at v0.8.0.
#
# WHY A RETRY AND NOT A FIX. The fix belongs upstream: bound the concurrency,
# and stop swallowing the read error -- the swallow is what turns a handle-limit
# problem into an afternoon of reading CI logs. revali is a different repository.
#
# WHY IT IS NARROW. A blanket `retry 3` would paper over a genuinely broken
# generator, which is the thing this codegen exists to catch. So the output is
# matched for the signature above: anything else fails on the first attempt, at
# full volume, exactly as before. That also keeps the retry honest -- if this
# script ever starts retrying, the log says which race it is retrying and why.
#
# WHY HERE AND NOT IN THE WORKFLOW. `sip run bootstrap test` and
# `sip run zonai compile` both reach this command, and so does a laptop. One
# wrapper means CI and a developer see the same behaviour, which is the same
# reason `test static` lives in scripts.yaml rather than in test.yml.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ATTEMPTS="${REVALI_GENERATE_ATTEMPTS:-4}"
SIGNATURE="Error initializing analyzer"

cd "${ROOT}/apps/server" || exit 1

# Announce itself, unconditionally. Without this line the wrapper is invisible
# in a passing log AND in a failing one -- the first time it went out, a windows
# leg failed with the exact race this exists to retry and printed none of the
# retry messages, and there was no way to tell "the wrapper never ran" from "the
# wrapper ran and the match failed". Both are plausible and they need opposite
# fixes, so the log has to say which.
echo "revali codegen via tool/ci/revali_generate.sh (up to ${ATTEMPTS} attempt(s))" >&2

for attempt in $(seq 1 "${ATTEMPTS}"); do
  output_file="$(mktemp)"

  # Redirected rather than piped through `tee`. A pipeline puts the exit status
  # behind `pipefail` and the captured output behind tee's buffering, and this
  # script's whole job is to read that status and that output -- so it does not
  # route either through something that can lose it. The output is echoed after
  # the fact instead, which costs ordering in the log and nothing else.
  if dart run revali dev --generate-only --flavor dev --release --recompile \
    >"${output_file}" 2>&1; then
    cat "${output_file}"
    rm -f "${output_file}"
    exit 0
  fi

  cat "${output_file}"

  if ! grep -q "${SIGNATURE}" "${output_file}"; then
    echo "revali codegen failed for a reason that is NOT the SDK-mirror race." >&2
    echo "Not retrying: this is about the tree, not about file-handle pressure." >&2
    rm -f "${output_file}"
    exit 1
  fi

  rm -f "${output_file}"
  echo "revali codegen lost the SDK-mirror race (attempt ${attempt}/${ATTEMPTS})." >&2

  if [ "${attempt}" -eq "${ATTEMPTS}" ]; then
    echo "Exhausted ${ATTEMPTS} attempts. This is the known upstream race, not a" >&2
    echo "broken tree -- but it has stopped being rare, which is worth acting on." >&2
    exit 1
  fi

  sleep 5
done
