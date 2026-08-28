# Dart SDK skew between a zonai host and its `.aot` workers

**Status: built.** A host binary and the AOT worker snapshots it loads
in-process must come from Dart SDKs that share a VM snapshot hash. Nothing tied
the two together, and one of the two ways they can disagree kills the host
process outright with no exception to catch. This is the record of what was
measured, what was built, and what is still missed.

## The coupling

`Mailman` can reach a worker three ways, and exactly one of them couples the
host to another SDK.

| path | what is loaded | coupled? |
|---|---|---|
| worker process (`db_config.exe`, `db_crons.exe`, …) over stdin/stdout | a standalone executable with its own embedded runtime | **no** |
| isolate from generated `.dart` source (dev, on the Dart VM) | source, JIT-compiled at spawn | **no** |
| isolate from an AOT snapshot (`db_operations.aot`, `db_rules.aot`) | a VM snapshot loaded into *this* process | **yes** |

The `.exe` workers are separate processes. `dart compile exe` embeds a runtime
in each one, so an `.exe` compiled by any SDK runs beside a host compiled by any
other — they only ever exchange bytes over a pipe, and the `.protocol` and
`.contract` stamps already guard what those bytes mean. The JIT branch hands
`Isolate.spawnUri` a `.dart` file, and the VM that would compile it *is* the VM
already running, so host and compiler cannot skew apart there.

Only the third path loads foreign machine code into the host's own VM. There is
exactly one `Isolate.spawnUri` in `apps/zonai` (`mailman.dart:836`) and exactly
two things that produce an `.aot` (`rules.dart` and `operations.dart`), so the
coupled surface is that narrow and can be enumerated.

## Where the two SDKs come from

They are chosen by two mechanisms that never consult each other.

- **The host.** CI pins `sdk: "3.13.2"` in **18 workflow job definitions**, so a
  released `zonai` embeds a 3.13.2 runtime. A project binary compiled by
  `zonai compile` / `zonai build` embeds whatever compiled *it*.
- **The snapshots.** Compiled by whatever `DartExecutable.resolve()` finds on
  the developer's machine (`rules.dart:123`, `operations.dart:143`). On the
  machine this was measured on, that was 3.13.2.

## Compatibility follows the hash, not semver

Measured on macos-arm64, reading the 32-hex string out of each SDK's
`bin/dartaotruntime`:

| SDK    | VM snapshot hash                   |
|--------|------------------------------------|
| 3.12.0 | `41be3daaabd524b8aa7423bc24584957`  |
| 3.12.1 | `ace654289f5abc240509fc941453ebc5`  |
| 3.12.2 | `ace654289f5abc240509fc941453ebc5`  |
| 3.13.1 | `0451907c2eaa8467e848c0067bfe8ed4`  |
| 3.13.2 | `0451907c2eaa8467e848c0067bfe8ed4`  |

3.12.1 and 3.12.2 share a hash and spawn each other's snapshots in both
directions. 3.12.0 does **not** share theirs and does not, despite sharing a
minor with both. Hash equality predicted all **eight** measured spawn outcomes.

A semver range would therefore be wrong in *both* directions — it would reject
compatible pairs (3.13.1/3.13.2 across a range boundary) and accept
incompatible ones (3.12.0/3.12.1). **The hash is the comparison, and no SDK
version is declared in any pubspec**; `environment.sdk` stays an ordinary
language range. A version string is carried alongside the hash for exactly one
purpose — so a message can say "requires Dart 3.12.0, you are on 3.13.2"
instead of printing two hex strings at somebody. It is never compared, and a
version that disagrees with the hash is the version being wrong.

## Two failure modes, and only one is survivable

**Same container format, different hash.** A catchable
`IsolateSpawnException: Wrong full snapshot version, expected 'X' found 'Y'`.
Mailman's existing `try`/`catch` around the spawn has always handled this
correctly, and would have continued to.

**Across a container-format change** — a 3.12.x host handed a 3.13.x snapshot:

```
snapshot_utils.cc:269: error: Failed to resolve symbol 'kDartIsolateSnapshotData'
```

SIGABRT, **exit 134**, with a native stack dump. This happens inside the VM's
snapshot loader *before any Dart code runs*. There is no exception, the `catch`
never executes, and the host process is gone along with every in-flight
request. **This is the failure the guard exists for**, and it is why the guard
has to decide *before* the spawn rather than around it — a `try`/`catch` cannot
be made to cover it at any price.

Both modes were measured in a scratch host/worker matrix built from real SDK
installs, not inferred from the VM sources.

## The window where it actually bites

Not "any two SDKs". The host and the snapshot compiler have to be genuinely
different processes, which needs a **stock released binary as host plus locally
recompiled snapshots**:

- A developer running a downloaded `zonai` (3.12.0 runtime) against a project
  whose `.aot` files their own 3.13.2 just compiled.
- **A `zonai build` bundle.** `_bundlePublishedBinary` copies
  `Platform.executable` — the running binary, byte for byte, including its
  embedded runtime — to `settings.buildExecutablePath` (`build.dart:219`),
  landing a CI-compiled host directly next to snapshots the local SDK produced
  moments earlier. The bundle is the assembled shape of exactly the hazard.

Running from source is never in the window: the host *is* the Dart VM that
would compile the workers. Nor is a machine whose only SDK is the one that
built the binary.

## What was built

Five pieces, in the order a hash travels through them.

| | |
|---|---|
| `domain/vm_snapshot_hash.dart` | the one way to obtain a hash, and the one place that knows what one looks like |
| `tool/ci/vm_snapshot_defines.sh` | the same derivation in bash, for the released CLI's bare `dart compile exe` |
| `domain/snapshot_sdk_stamp.dart` | the `.sdk` sidecar — write, read, and the incompatibility decision |
| `domain/dart_sdk/dart_sdk_check.dart` | tells a developer their SDK has drifted, before they build something that cannot run |
| `db_mutator/mailman.dart` | consults the sidecar ahead of the spawn (`:816`, immediately before `:836`) |

### The host learns its own hash at compile time

A compiled host has no `dartaotruntime` beside it to read, and **its own bytes
are not a reliable source** — a small test binary happened to contain exactly
one 32-hex run, but nothing guarantees that for a real payload, so that route
was rejected rather than merely untried. Compile time is the only chance.

`dart compile exe --define=K=V` plus a `const String.fromEnvironment('K')`
round-trips; verified. The host is stamped at two sites:

- **The released CLI** — `scripts.yaml:550` runs `tool/ci/vm_snapshot_defines.sh`
  and splices its output into the bare `dart compile exe` at `scripts.yaml:570`.
- **The linked project binary** — `project_binary.dart:83` appends
  `vmSnapshotDefines(dartExecutable)` to the compile arguments.

Two details there are measured, not assumed:

- **The defines go AFTER `env.dartDefineArgs`.** With `dart compile exe`
  3.12.0, the *last* occurrence of a duplicated key wins. Placed first, a
  project's own `.env` naming `ZONAI_VM_HASH` would silently replace the stamp
  with a value of its choosing and the guard would believe it. A round trip
  with `-DZONAI_VM_HASH=an_env_file_lie` ahead of the real define reported the
  real hash out of the compiled binary.
- **The hash is derived on the release path, never written down.** A literal
  beside those 18 `sdk: "3.13.2"` pins would be correct until the next bump and
  silently wrong afterwards — and a binary claiming a runtime it does not have
  is worse than one claiming none, because the guard trusts it. The script reads
  the SDK actually on `PATH`, i.e. the one about to run the compile two lines
  down, and **exits non-zero rather than emitting an empty define**. An
  unstamped binary is a supported state; it is not one to arrive at by accident
  on the release path.

### Finding the hash in a binary is not a naive grep

Both implementations scan for **maximal runs** of lowercase ASCII hex that are
exactly 32 characters long, and accept only when the file holds exactly one
*distinct* such run.

This is the part that fails silently if you get it wrong. Measured against the
real 3.12.0 `dartaotruntime`, the windowed spelling `grep -o '[0-9a-f]\{32\}'`
returns **seven** distinct values — six of them 32-character windows inside
long slabs of repeated `'4'`s and `'5'`s from zero-fill regions — while the
maximal-run spelling returns exactly the hash. "We found the hash" and "we
stopped looking properly" are the same observation to a naive scan.

Uppercase is excluded on purpose in both: the VM writes the hash lowercase, and
accepting uppercase only widens the set of unrelated strings that can collide
with it. **The two definitions must agree** — the one baked in by bash is
compared at runtime against the one Dart reads out of an SDK, so a divergence
would read as a mismatch between SDKs that are in fact identical.

### The snapshot carries a sidecar, and unknown means DO NOT SPAWN

`writeSnapshotSdkStamp` runs immediately after each successful
`dart compile aot-snapshot`, beside the existing `writeMessageContractStamp`
(`rules.dart:142`, `operations.dart:162`). It writes two lines — hash first, so
the compared value sits at a fixed position and a future third line cannot
displace it — to a sidecar whose extension is **appended**:
`db_operations.aot.sdk`, not `db_operations.sdk`. The `.protocol` scheme
replaces the extension and so cannot tell `db_operations.exe` from the
`db_operations.aot` beside it; those are separate compiles that have diverged
before.

The hash recorded is the **compiling SDK's**, not the running process's. The
two differ in exactly the case the sidecar exists for, and it is not
hypothetical: running the CLI under the pinned 3.12.0 toolchain in
`e2e/build_smoke` produced snapshots compiled by the machine's `PATH` 3.13.2,
and the stamps correctly read `0451907c…` / `3.13.2` rather than `41be3d…` /
`3.12.0`. Reading the host's own would have recorded the one number that can
never disagree.

`isSnapshotSdkIncompatible` **inverts what its two siblings do with an
unknown.** `isProtocolStale` and `isMessageContractStale` both answer "not
stale" when either side is missing, because unknown is not the same as wrong
and refusing every pre-existing artifact would break more than it catches. Here
the two costs are not comparable:

| | cost |
|---|---|
| false negative | uncatchable SIGABRT — the host dies with every in-flight request |
| false positive | Mailman falls back to the `.exe` worker, which serves identically; only in-process dispatch is lost |

So **every** way of failing to establish compatibility answers "incompatible":
no stamp, an unreadable stamp, a missing snapshot, and a host that does not know
its own hash. Only a present snapshot, with a readable stamp, naming exactly the
host's own hash, is allowed to spawn.

Writing a stamp with a `null` hash **deletes** any stamp already there rather
than leaving it. An orphan would have the next spawn compare a fresh snapshot
against the SDK of the build before it — and since a match here authorises
loading foreign machine code into this process, that is the one outcome worth
going out of the way to prevent.

Mailman **declines rather than throws**, for the same reason
`_snapshotContractIsStale` does, and names which of the four refusals it was.
"No stamp" and "wrong stamp" ask different things of whoever reads them, and
collapsing them into a single "SDK mismatch" would send someone recompiling a
snapshot that is fine.

### The developer is told before they build something that cannot run

`DartSdkCheck.ensure()` runs once at `zonai_runner.dart:85`, before command
dispatch, so one call covers every command and the warning fires once per
process. It compares `hostVmSnapshotHash` against
`sdkVmSnapshotHash(await resolveDartExecutable())`.

**Severity is split.** `zonai compile` and `zonai build` **refuse with exit 1**
— they are the only commands that write an `.aot`, so they are the last moment
before a bad artifact exists on disk. Every other command warns and proceeds.
`--no-dart-sdk-check` turns it off; the refusal says so.

**Unknown here is silence, not alarm** — the opposite call from the spawn-time
guard, deliberately, because the cost of being wrong is opposite. A spawn-time
guard's mistake is a crash it could have prevented, so it is entitled to refuse
on doubt. This check's mistake is a false alarm telling a developer their
perfectly good toolchain is broken, aimed at a human who cannot verify it and
who will either act on it or learn to ignore every warning this CLI prints.
Between those, silence is the cheaper error.

It also no-ops entirely when running from source, and returns silently when
`DartExecutable.resolve()` finds no SDK at all — the ordinary state of a
deployed bundle on a box with no Dart installed, which compiles nothing and is
in no danger. Taking the command down there would be the check causing the
outage it exists to prevent.

## Watched working

A trunk proof run after the pieces were integrated, driving the real derivation
and the real decision against the two SDKs actually installed on this machine:

```
stamped: hash=41be3daaabd524b8aa7423bc24584957 version=3.12.0
host 3.12.0 hash=41be3daaabd524b8aa7423bc24584957
host 3.13.2 hash=0451907c2eaa8467e848c0067bfe8ed4

matching host ACCEPTS stamped snapshot : true   (want true)
skewed host   REFUSES stamped snapshot : true   (want true)
unstamped snapshot REFUSED             : true   (want true)
```

Alongside that, the derivation was verified against real SDKs rather than only
fixtures — `41be3daaabd524b8aa7423bc24584957` / `3.12.0` for the pinned
toolchain and `0451907c2eaa8467e848c0067bfe8ed4` / `3.13.2` for the machine
default resolved by bare name on `PATH`, both matching the table above. A binary
compiled with those defines read them back through `hostVmSnapshotHash`; one
compiled without reported `null` for both, which is the safe direction.

78 unit tests cover the pieces, all passing under the pinned 3.12.0 toolchain
on 2026-08-27: 32 in `vm_snapshot_hash_test.dart`, 18 in
`snapshot_sdk_stamp_test.dart`, 5 in `mailman_snapshot_sdk_guard_test.dart`
(including one pinning that the JIT source branch is *not* subject to the
guard), 19 in `dart_sdk_check_test.dart`, 4 in `dart_sdk_test.dart`.

Mailman's host hash and SDK version are constructor-injected. Both are
`String.fromEnvironment` constants and therefore empty under `dart test`, so
without the seam the guard's *passing* direction is unreachable from a test —
and a guard only ever observed refusing cannot be told apart from one that
refuses everything.

## What it still misses

- **Every zonai binary released before this change now declines in-process
  dispatch entirely.** Such a host has a `null` `hostVmSnapshotHash`, and under
  "unknown means do not spawn" it refuses every snapshot it is offered. This is
  intended and it is not degradation to nothing — the host still serves every
  request through the worker process — but it is a real behaviour change for
  existing binaries, and it warns once per snapshot path saying so.

- **`tool/ci/test_vm_snapshot_defines.sh` is not wired into anything.** It is a
  real harness with real cases — including the seven-values regression above and
  a case driving the script against whichever SDK is on `PATH` — and nothing in
  `scripts.yaml`, `.github/workflows/`, or `.game_loop/verify.yaml` references
  it. Grepped, not assumed: the file has zero references outside itself. Until
  it is called, the two failure modes it was written to catch are uncaught, and
  the script that decides what runtime identity every released binary claims has
  no running controls. `scripts.yaml`'s `static` target (`:271`) already runs
  several sibling `tool/ci/check_*.sh` scripts, which is where it belongs.

- **Nothing checks that the bash and Dart definitions of "a hash" agree.** They
  were written to agree and have been observed agreeing on two SDKs, but that is
  an observation, not a control. If they drift, the symptom is a *reported
  mismatch between SDKs that are identical* — a false refusal, which is the safe
  direction, but a confusing one to debug.

- **Windows and Linux are unmeasured.** Every hash in the table above is
  macos-arm64. The mechanism has no platform-specific logic beyond the `.exe`
  suffix on `dartaotruntime`, and the *hashes themselves are expected to differ
  per platform* — which does not matter, since a host and its snapshots are
  always on the same one. But the "exactly one distinct 32-hex maximal run"
  property of `dartaotruntime` has only been confirmed on macos-arm64, for 3.12.0
  and 3.13.2. If it does not hold elsewhere, the release build fails loudly
  (the script exits non-zero) rather than shipping something wrong.

- **A layout change makes this UNKNOWN, not wrong.** If a future SDK stops
  shipping `bin/dartaotruntime`, or ships one with two distinct 32-hex runs, the
  CLI reads `null` and treats it as unknown — the release script refuses, and
  the runtime guard falls back to the worker process. Nothing silently
  mis-identifies an SDK.

- **The `.exe` workers carry no `.sdk` stamp, and should not.** They are
  separate processes with their own embedded runtimes; there is no coupling to
  guard. Named here so the asymmetry with `.protocol`/`.contract` reads as a
  decision rather than an oversight.

- **The framing check on the snapshot path**, unchanged from
  `docs/stale-worker-guard.md`: `.protocol` still cannot distinguish a `.aot`
  from its sibling `.exe`. `.sdk` solved that for itself by appending rather
  than replacing the extension; `.protocol` was left alone.

## See also

- `docs/stale-worker-guard.md` — the `.contract` sidecar, the first two of the
  three stamps, and the reasoning the `.sdk` sidecar's shape was copied from.
- `docs/known-issues.md` #19.
