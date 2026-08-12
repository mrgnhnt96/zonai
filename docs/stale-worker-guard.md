# Catching a stale worker before it crashes

Handoff doc. There is already a guard that refuses a version-skewed worker.
It does not fire for the kind of skew that actually bit us, and when it doesn't
fire the failure is unreadable. This is what it misses, what to key on instead,
and — most of it — what the failure has to look like when it does fire.

## What exists

`apps/zonai/lib/src/domain/ipc_protocol_stamp.dart` writes a `.protocol`
sidecar next to every compiled worker holding `IpcCodec.version` (currently
`1`). `WorkerProtocolMismatchException.forStamp` compares it to the host's
before `Mailman` spawns anything, and refuses on a disagreement.

It exists for one specific event: `066b88b` swapped the wire format from
newline-JSON to framed MessagePack, with no backward compatibility. It answers
**"can these two binaries talk to each other at all?"**

## What it misses

The framing is not the only thing that has to agree. The *vocabulary* inside
the frame does too, and nothing records that.

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

## Why this is worth doing now

`zonai_schema` 0.2.0 raises the floor the CLI declares, so everyone upgrading
has to rebuild their workers (`docs/releasing.md` says so, and the changelog
says so). A stale worker is therefore the *expected* failure mode of this
release — and it is precisely the one the guard is blind to. Shipping a release
that causes worker rebuilds while the stale-worker guard can't see them is the
wrong order.

## What to key on — three options

**(a) Bump `IpcCodec.version` on every vocabulary change.** Cheapest. Also
wrong twice: it makes a framing constant mean something it doesn't, and it
relies on someone remembering — the same failure mode the version mirror had.
A guard nobody bumps is not a guard. Not recommended, but worth naming so the
next person doesn't rediscover it as an idea.

**(b) Stamp a hash of the message contract.** At worker-compile time, hash the
sources that define what crosses the wire — the `Request`/`Response` subclasses
under `libs/zonai_schema/lib/src/handlers/**` and the enums they parse
(`RateLimitOperation`, `AuthExtensionStep`, …) — and write it beside the
executable like the protocol stamp. Any change to the vocabulary changes the
hash, with nobody having to notice.

Cost: the hash must cover exactly the right files. Too narrow and it misses a
change; too broad (all of `lib/src`) and every unrelated edit forces a rebuild,
which trains people to ignore it. Worth writing down which files are in the set
and why, next to the hash function.

**(c) Stamp the resolved `zonai_schema` version.** Trivial, and it composes
with `kMinSchemaVersion`: record which schema version each worker was built
against, refuse when it is below the host's floor.

Its weakness is exactly where the bug was found: in this monorepo (and any
project using a path dependency) `zonai_schema` has no resolved version, so
this degrades to "unknown" — and `isProtocolStale` treats unknown as not-stale
on purpose. Consumers on pub.dev would be covered; the people developing zonai
would not.

**Recommendation: (b), with (c) as a cheap first cut** if it needs to ship
alongside the release. They compose — (c) covers the hosted case in an
afternoon, (b) covers the path-dependency case properly. Do not do (a).

## The failure has to be loud

This is the part that matters more than which key is chosen. **A guard that
detects staleness and then reports it badly has not solved this.** The
observed failure above is the anti-pattern: a 503 carrying a Dart stack trace,
from which nothing about the actual problem or its fix is recoverable.

Required, when the guard fires:

1. **Fail before doing work, not mid-request.** Refuse at spawn, the way
   `WorkerProtocolMismatchException` already does. A stale worker must never
   get far enough to fail inside a request handler, because there the failure
   arrives as a 5xx to an end user rather than as a message to the operator.
2. **Name the thing.** Which worker, and its path on disk. "A worker is stale"
   is not actionable when there are six of them.
3. **Show both sides.** What the worker was built with, what this host
   expects. A reader has to be able to see the gap, not take our word that
   there is one.
4. **Say why it happened**, in terms of something the reader did — upgraded
   `zonai_schema`, pulled a newer CLI, restored an old build directory. Not
   "hash mismatch".
5. **Give the exact command.** `zonai compile` for a dev project;
   `zonai build` + redeploy for a deployed bundle. State which case is which —
   `zonai compile` only refreshes workers in a bundle, not the bundle itself,
   and that distinction has caught people out.
6. **Never degrade silently.** Not to a warning, not to "unknown, carry on"
   *once staleness is actually established*. Unknown (no stamp) may pass;
   known-and-different must not.

`WorkerProtocolMismatchException.message` already does all six and is the shape
to copy:

```
RATE_LIMITS worker (.zonai/executables/db_rate_limit.exe) speaks IPC protocol
v1 but this host speaks v2.
The host binary and this worker were compiled at different times across a
wire-format change. Run `zonai compile` -- it detects a stale dev host binary
and rebuilds it automatically. If this host is a deployed `zonai build` bundle
instead (compile only refreshes workers there, not the bundle), rebuild with
`zonai build` and redeploy.
See https://docs.zonai.dev/cli/upgrading
```

Reuse it rather than writing a second, worse one — either by extending
`WorkerProtocolMismatchException` with a second cause, or by adding a sibling
that follows the same template.

## How to verify a fix

Reproduce first, because a guard nobody has watched fail is not known to work:

1. Build workers, then change the vocabulary underneath them — add a value to
   an enum a request parses, without touching `IpcCodec.version`.
2. Rebuild the host only, leaving `.zonai/executables/` alone.
3. Send a request that uses the new value.

Before: HTTP 503 with `No enum value with that name: …`. After: refused at
spawn with a message naming the worker, both versions, and the command.

Assert on the *message*, not just the exception type. Every requirement above
is about what the text says, so a test that only checks `throwsA(isA<…>())`
leaves the whole point untested.

## What it will still miss

- A worker whose stamp is **missing** — built before stamping existed, or
  compiled outside `zonai compile`/`zonai build`. That stays "unknown, not
  wrong" by design; the alternative refuses every ad-hoc fixture.
- Divergence that isn't in the hashed set, under (b). Say out loud which files
  are covered, so the gap is visible rather than assumed shut.
- Anything about whether the worker is *correct* — only whether it was built
  from the same contract.
