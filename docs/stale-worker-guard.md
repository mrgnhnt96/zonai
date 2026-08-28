# Catching a stale worker before it crashes

**Status: built.** This was a handoff doc; it is now the record of what was
built, what was watched happening, and what is still missed. The diagnosis is
kept because the reasoning behind the file set only makes sense next to it.

## The failure

`apps/zonai/lib/src/domain/ipc_protocol_stamp.dart` writes a `.protocol`
sidecar next to every compiled worker holding `IpcCodec.version` (currently
`1`). `WorkerProtocolMismatchException.forStamp` compares it to the host's
before `Mailman` spawns anything, and refuses on a disagreement. It exists for
one specific event: `066b88b` swapped the wire format from newline-JSON to
framed MessagePack, with no backward compatibility. It answers **"can these
two binaries talk to each other at all?"**

The framing is not the only thing that has to agree. The *vocabulary* inside
the frame does too, and nothing recorded that.

#25 added `custom` to the `RateLimitOperation` enum. `IpcCodec.version` stayed
`1` — correctly, the framing didn't change — so the stamp matched and
`isProtocolStale` returned `false`. But the host now sends
`operation: "custom"`, and a worker compiled before that value existed cannot
parse it.

Observed on 2026-08-12, in `apps/playground`, with a `db_rate_limit.exe` from
2026-08-07 whose `.protocol` read `1` against a host also on `1`:

```
{"error":"RATE_LIMITS worker failed (exit code: 255)
Unhandled exception:
Invalid argument (name): No enum value with that name: \"custom\"
#0      EnumByName.byName (dart:core/enum.dart:180)
#1      new RateLimitRequest.fromRequest (package:zonai_schema/src/handlers/rate_limits/rate_limit_request.dart:18)
..."}
```

HTTP 503, a raw Dart stack trace in the response body, and nothing anywhere
saying the word "stale" or "rebuild".

Adding an enum value widens what the host can *say* without changing how it is
*said*. Same for a new required field on a request, a renamed payload key, or a
new `Request` subtype — all invisible to a codec-version check.

## What was built

Option (b) from the original three: **a hash of the message contract, stamped
beside the executable.**

| | |
|---|---|
| `domain/message_contract_hash.dart` | resolves `zonai_schema`, walks the file set, hashes it |
| `domain/dart_source_normalizer.dart` | strips comments and collapses whitespace before hashing |
| `domain/message_contract_stamp.dart` | the `.contract` sidecar, and which hash the host speaks |
| `db_mutator/worker_contract_mismatch_exception.dart` | the refusal, and its message |

`writeMessageContractStamp` runs beside `writeProtocolStamp` at all seven
compile sites (six workers plus the project binary), on the two AOT snapshots,
and in `_bundlePublishedBinary` so a bundle that ships the stock CLI still
records what it was assembled against. `Mailman._throwIfContractMismatch` runs
at spawn, immediately after the protocol check. `zonai compile` rebuilds a host
binary whose stamp is stale *or missing* — the second case matters, because an
unstamped host has nothing to compare and would leave the guard inert forever.

The sidecar *appends* rather than replaces: `db_operations.exe.contract`, not
`db_operations.contract`. The `.protocol` stamp replaces the extension, and
that scheme cannot tell `db_operations.exe` from the `db_operations.aot`
snapshot beside it — they would claim the same file. Two artifacts compiled by
separate invocations need two stamps; rules.dart's note on `compileArgs`
records the time those two invocations came out different.

### Both spawn paths

`Mailman` can reach a worker two ways, and only one of them was covered at
first.

- **Process** (`.exe` over stdin/stdout) — `_throwIfContractMismatch` refuses.
- **Isolate from generated source** (dev, on the Dart VM) — JIT-compiled at
  spawn from the current sources. It *is* the host's sources; it cannot be
  stale, and nothing checks it.
- **Isolate from an AOT snapshot** (`db_operations.aot`, `db_rules.aot`; taken
  on a compiled host, which is the ordinary production shape) —
  `_snapshotContractIsStale` declines it.

That third one **declines rather than throws**, which reads as the weaker
choice and isn't. Returning `false` from `_tryStartIsolate` falls through to
the worker process, which carries its own stamp and refuses loudly if it is
stale too — so a genuinely stale pair still fails at spawn with the full
message. What the soft decline buys is the case where the two have *diverged*:
a stale snapshot beside a fresh executable then costs in-process dispatch
rather than the request. It logs a warning naming both contracts and the
command, once per path.

The protocol check was left alone on the snapshot path. Covering it would mean
changing `.protocol`'s naming scheme, which is a format already on disk in
every existing project, for a gap that opens only when the framing changes —
twice, in the project's life. Not worth the churn today; named here so the
asymmetry is a decision rather than an oversight.

Options (a) and (c) were not taken. (a) — bumping `IpcCodec.version` on every
vocabulary change — makes a framing constant mean something it doesn't and
relies on someone remembering. (c) — stamping the resolved `zonai_schema`
version — degrades to "unknown" for every path dependency, which is where the
bug was found; it is subsumed by (b) anyway, since a version bump changes the
sources and therefore the hash.

### Which files are hashed

Every Dart file inside `zonai_schema`'s `lib/` reachable through
`import`/`export`/`part` from anything under `lib/src/handlers/`. 207 files at
the time of writing, of 260 in the package.

The set is *computed, not curated*, and that is the point. The obvious
hand-drawn boundary — `lib/src/handlers/**` and nothing else, which is what
this doc originally proposed — would have missed the bug that prompted the
whole exercise: `RateLimitOperation` lives in
`lib/src/types/rate_limit_operation.dart`, one import away from the handler
that parses it. A boundary a person draws is a boundary a person has to
remember to redraw.

It errs broad on purpose. Too broad costs a worker rebuild nobody needed; too
narrow costs the 503 above. The cost of broad is paid down by hashing
*normalized* source: comments and whitespace are stripped, so doc edits and
`dart format` — which is most of what actually changes in these files — do not
count. Verified against the real sources:

| edit | hash |
|---|---|
| rewrite a doc comment | unchanged |
| reflow with blank lines and indentation | unchanged |
| add a value to `RateLimitOperation` | **changed** |
| rename `'customOperation'` to `'custom_operation'` | **changed** |

## The failure has to be loud

This mattered more than which key was chosen. **A guard that detects staleness
and then reports it badly has not solved this.** The observed failure above is
the anti-pattern: a 503 carrying a Dart stack trace, from which nothing about
the actual problem or its fix is recoverable.

Six requirements, each one now asserted on the message text in
`worker_contract_mismatch_exception_test.dart` — a test that only checked
`throwsA(isA<…>())` would leave the whole point untested:

1. **Fail before doing work, not mid-request.** Refuse at spawn.
2. **Name the thing** — which worker, and its path on disk.
3. **Show both sides**, so a reader can see the gap rather than take our word.
4. **Say why it happened**, in terms of something the reader did.
5. **Give the exact command**, and say which case is which.
6. **Never degrade silently** once staleness is actually established.

What it produces:

```
CONFIG worker (.zonai/executables/db_config.exe) was built against message
contract 765731660f2b but this host speaks 2f4a6becd11d.
The wire format still matches -- what changed is the vocabulary inside it: an
enum value, a request field, or a payload key that this worker was compiled
before. Upgrading `zonai_schema`, pulling a newer CLI, or restoring an older
build directory all do this. Left alone the worker would start and then fail
part-way through a request.
Run `zonai compile` -- it rebuilds every worker, and a stale dev host binary
with them. If this host is a deployed `zonai build` bundle instead (compile
only refreshes workers there, not the bundle), rebuild with `zonai build` and
redeploy.
See https://docs.zonai.dev/cli/upgrading
```

## Watched failing

A guard nobody has watched fail is not known to work. In `apps/playground`, on
2026-08-12: `zonai compile` to stamp the workers, then a value added to
`RateLimitOperation` without touching `IpcCodec.version`, then `zonai serve`
(the JIT dev host, so the host is the edited sources while the workers on disk
are not).

| state | result |
|---|---|
| stamped, contract drifted | **refused at spawn** — the message above, before the server bound a port |
| `.contract` files deleted, same drift | server started and served (HTTP 302 on `/_`) |
| stamped, no drift | server started and served |

The middle row is the world before this change, and is also the deliberate
"unknown passes" behaviour: nothing to compare, so nothing refused. The
refusal in the first row arrives during startup config resolution, not as a
5xx to a caller — requirement 1, observed rather than asserted.

### The snapshot path

Harder to reach: it needs a compiled host that is *also* using Mailman for
ops/rules, and in this monorepo a project always links (zonai's sources are on
disk beside the CLI, so `resolveProjectLink` merges the graphs and ops run
in-process, never touching Mailman). `ZONAI_FORCE_WORKERS=true` against the
compiled `.zonai/zonai` is the way in — it turns off in-process dispatch
without changing anything the guard reads.

Driving `zonai db admin list` through it, with `db_operations.exe.contract`
and `db_operations.aot.contract` set independently:

| `.aot` | `.exe` | result |
|---|---|---|
| fresh | fresh | `Started isolate worker` — snapshot used, in-process dispatch kept |
| **stale** | fresh | warning, fell through to `db_operations.exe`, command succeeded |
| **stale** | **stale** | warning, then the refusal — `Failed to list admin accounts: … OPERATIONS worker … was built against message contract 000000000000 but this host speaks 765731660f2b` |

Row two is the case the soft decline exists for, and is the reason the two
artifacts needed separate stamps: under the old shared-sidecar scheme it could
not have been expressed, let alone observed.

## What it still misses

- **A worker whose stamp is missing.** Unknown, not wrong, by design — the
  alternative refuses every ad-hoc fixture. Row two above is what that looks
  like.
- **The published CLI acting as host** — still missed, but it now *says so*.
  A released `zonai` serving a project directly (`zonai serve`, `zonai db …`)
  is built with `__ZONAI_COMPILED__=true` by the bare `dart compile exe` at
  `scripts.yaml:570` (which `compile.yml` reaches through `sip run zonai
  compile` — that file contains no `dart compile exe` of its own, contrary to
  what this doc and `docs/linking-a-bare-released-binary.md` both said until
  2026-08-27). No **contract** stamp is written there, so
  `hostMessageContractHash` looks for a sidecar beside
  `Platform.resolvedExecutable`, finds none, and everything passes.

  "Nothing stamps it" was true of that compile until 2026-08-27 and is no
  longer: it now bakes in `ZONAI_VM_HASH` and `ZONAI_DART_SDK` via
  `tool/ci/vm_snapshot_defines.sh` (`scripts.yaml:550`). That is a *different*
  stamp for a different hazard — which VM snapshot format the host can load,
  not which message vocabulary it speaks — and it does nothing for this gap.
  See `docs/dart-sdk-skew.md`. The reason the two were solved differently is
  the one below: a hash baked into the CLI cannot describe a project's
  contract, whereas the VM snapshot hash is a property of the binary itself and
  describes nothing else.

  **This has nothing to do with project linking**, which is how it was first
  written down here and in `docs/linking-a-bare-released-binary.md`.
  `maybeReexecProjectRuntime` returns at `if (kIsCompiled) return null`
  (`project_runtime.dart:58`) — *before* it ever calls `resolveProjectLink`.
  A compiled CLI is the host whether or not the project could link, so closing
  the linking case would not close this. The two are independent.

  It is also narrower than "every consumer": `_bundlePublishedBinary` stamps
  the binary it bundles, so a deployed `zonai build` bundle carries a stamp and
  the guard runs there. What is uncovered is the CLI used *in place* — which is
  the developer's own loop, and therefore where `zonai_schema` actually moves.

  Not closed on purpose. One CLI serves many projects, so a sidecar beside it
  cannot describe any of them. Baking the hash in at CLI-build time *would*
  work, but it would compare the CLI's compiled-in `zonai_schema` against the
  project's on exact equality — turning `SchemaVersionCheck`'s deliberate
  "at or above the floor is fine" into "identical or refuse", and refusing a
  consumer on 0.2.0 with a CLI shipping 0.2.1. Hashing the project's sources
  instead would measure the wrong thing entirely: the CLI parses worker
  messages with the schema compiled into it, not with whatever is on disk.

  So the gap stays, and `Mailman._warnIfContractGuardInert` states it instead.
  It adds no refusal — with no host contract there is nothing to refuse *on*,
  since a stale worker and a fresh one are the same observation — and it fires
  once per process, at the spawn where the comparison would have happened
  rather than at startup, so commands that never reach a worker stay quiet. It
  is conditioned on the *worker* being stamped: with nothing stamped on either
  side no comparison was ever available to lose, and a project that has not run
  `zonai compile` yet would only be getting noise.
  `hostContractUnknownReason` supplies the sentence, and takes `isCompiled` /
  `readStamp` as seams because `kIsCompiled` is a compile-time `false` under
  `dart test`.

  Watched, in `apps/playground` on 2026-08-12, against the compiled
  `.zonai/zonai` under `ZONAI_FORCE_WORKERS=true` (the same way in as the
  snapshot rows above), driving `zonai db admin list`:

  | host stamp | worker stamps | result |
  |---|---|---|
  | present | present | silent — the guard ran |
  | **removed** | present | the warning, once, on the first spawn; command still succeeded |
  | removed | **removed** | silent — nothing to lose |

  Removing the host's stamp is a stand-in for a released binary, not the thing
  itself: it produces the same state `hostMessageContractHash` reads, but it
  cannot be reproduced in this repo any other way — see
  `docs/linking-a-bare-released-binary.md` on why.

  This is the one case where the coarse guard is the right one:
  `SchemaVersionCheck` no-ops for path dependencies but *works* for exactly
  this consumer, because they have a resolved `zonai_schema` version in
  `pubspec.lock`. The two are complementary — a version floor where a hash
  cannot go, a hash everywhere the version is unknowable.
- **The framing check on the snapshot path.** `.protocol` still can't
  distinguish a `.aot` from its sibling `.exe`; see above for why that was
  left.
- **Anything outside `zonai_schema`.** A change to the host's own message
  handling in `apps/zonai` that never touches the schema is not in the
  closure.
- **A stock-binary bundle's own vocabulary.** `_bundlePublishedBinary` stamps
  the bundle with the contract it was *assembled* against, not with what the
  published binary was compiled from. That catches later drift, which is what
  this guard is for; a published CLI already out of step with the project's
  `zonai_schema` is `SchemaVersionCheck`'s job.
- **Its own silence.** `MessageContractHash.compute` never throws — a
  staleness check that takes down the thing it is checking is worse than no
  check — so anything it cannot answer becomes "unknown" and passes. If it
  breaks, it breaks quiet.
- **Whether the worker is *correct*.** Only whether it was built from the same
  contract.
