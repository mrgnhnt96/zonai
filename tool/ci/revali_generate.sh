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
# lines later as an analyzer that is missing part of the SDK.
#
# WHICH part is luck, so the failure has more than one face -- both of these were
# observed on the same job within an hour, and they are the same bug:
#
#   Error initializing analyzer / FileSystemException on the SDK's version file
#   Bad state: No definition of type Future   (TypeProviderImpl._getClassElement)
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
ATTEMPTS="${REVALI_GENERATE_ATTEMPTS:-6}"

# THE SIGNATURE IS A SET, because the race is polymorphic: what breaks depends on
# which file lost the read, and the mirror drops a different one each time.
# Both observed renderings are below, and a third is assumed to exist.
#
#   Error initializing analyzer        -- the SDK's version file was dropped, so
#                                         FolderBasedDartSdk.languageVersion throws
#                                         while the context is still being built.
#   Bad state: No definition of type   -- part of dart:async (or dart:core) was
#                                         dropped, so TypeProviderImpl cannot find
#                                         a class every Dart program has.
#
# Narrow enough to stay honest: both are crashes INSIDE package:analyzer, and
# neither is reachable from a genuine problem in this repo's source. Bad Dart in
# apps/server produces an analysis DIAGNOSTIC naming our file; it does not make
# the analyzer forget what `Future` is. If a third rendering shows up, add it
# here with the same test -- "could our code cause this?" -- and if the answer is
# yes, it does not belong in this list.
SIGNATURES='Error initializing analyzer|Bad state: No definition of type'

# The one file this step exists to produce. `server.sync-to-cli` asserts the same
# path immediately afterwards; checked here too so the failure is attributed to
# the command that actually failed rather than to the next one to notice.
ARTIFACT=".revali/server/server.dart"

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
  dart run revali dev --generate-only --flavor dev --release --recompile \
    >"${output_file}" 2>&1
  status=$?
  cat "${output_file}"

  # THE EXIT STATUS IS NOT THE VERDICT, and believing it was is why the first
  # two versions of this script never retried anything. `revali dev` prints the
  # crash, then EXITS 0. The wrapper saw success, returned success, and the
  # build walked on to fail minutes later in `dart compile exe` with "Error when
  # reading .revali/server/server.dart" -- a message about a missing file, three
  # steps away from the thing that failed to write it.
  #
  # So the artifact is the verdict. This step exists to produce that one file;
  # if it is not there, the step failed, whatever revali returned. That is also
  # what `server.sync-to-cli` checks one command later, which is the only reason
  # any of this was caught at all.
  if [ "${status}" -eq 0 ] && [ -f "${ARTIFACT}" ]; then
    rm -f "${output_file}"
    exit 0
  fi

  if [ "${status}" -eq 0 ]; then
    echo "revali exited 0 but did not write ${ARTIFACT}." >&2
  fi

  if ! grep -qE "${SIGNATURES}" "${output_file}"; then
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
