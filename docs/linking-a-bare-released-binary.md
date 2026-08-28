# Linking a bare released binary — the last case, and whether to close it

**Status: weighed on 2026-08-12 and closed as "accepted, not fixed".** The
residual is real and stays; the one thing that was going to be fixed alongside
it turned out to be a different bug with a different cause, and *that* got
fixed. Read "Where this landed" for the decision and "The stale-worker-guard
argument was wrong" for the retraction. Everything else is the reasoning it
rests on, kept because it is what a re-opener would have to re-derive.

The merged-`package_config` route for in-process ops/rules **was built and
shipped in v0.6.1** — `todo.md` said otherwise until this session and now
does not. `docs/build-fallback-next-steps.md` §2 describes what landed.

## What is actually left

From `build-fallback-next-steps.md`, verbatim, because the wording matters:

> **A bare released binary still falls back**, and always will: with no zonai
> sources on disk there is no second graph to merge.

That is the whole remainder. Not a bug, not an unbuilt feature — a structural
consequence of zonai shipping as a standalone binary that is never an
application dependency.

The mechanism, so it is not re-derived: `resolveProjectLink()`
(`apps/zonai/lib/src/domain/project/project_link.dart`) returns
`ProjectLink.direct()` when the project already resolves `package:zonai`,
otherwise calls `zonaiPackageConfigPath()`
(`apps/zonai/lib/src/utils/zonai_entrypoint.dart:31`), which walks up from the
current directory *and* from `Platform.script` looking for a
`.dart_tool/package_config.json` that resolves zonai to real sources. Found →
the two graphs merge and the project binary links. Not found →
`ProjectLink.skip`, and ops/rules go over Mailman IPC.

A user who downloaded `zonai` from a release has no such config anywhere above
either path. They always skip.

## Why it matters — and one reason it doesn't, which was wrong here first

One thing rides on the skip.

**Ops/rules dispatch over a pipe instead of in-process** — three call sites in
`zonai_db/parts/__utils.dart` (rules `:7`, operations `:20`, extensions `:362`).
No measurement of that cost exists; do not quote a number that has not been
taken. Plus `RateLimiter.isRegisteredCustomOperation`
(`services/rate_limiter.dart:44`) can only answer when rules are linked, so
per-operation rate limiting falls back to the coarse per-table `.custom`
bucket. Not an authorisation hole — the rules layer still denies unregistered
operations — but it is fine-grained limiting quietly not running.

### The stale-worker-guard argument was wrong — retracted

This doc previously claimed a second consequence: that when nothing links,
`maybeReexecProjectRuntime` returns null, the CLI becomes the host, and the
message-contract guard therefore goes inert — so closing linking would close
the guard gap for free. **It would not.** The chain does not run through
linking at all:

```dart no-analyze
// project_runtime.dart:56
Future<int?> maybeReexecProjectRuntime() async {
  if (HostWorkerRegistries.hasOperations) return null;
  if (kIsCompiled) return null;          // <- a released binary returns here
  ...
  final link = resolveProjectLink();     // <- never reached by a released binary
```

`kIsCompiled` is checked at `:58`; `resolveProjectLink()` is not called until
`:80`. A compiled CLI is the host **whether or not the project could link**, so
a bare binary that could suddenly link would still serve as an unstamped host
and the guard would still be inert. The two facts are independent and only
coincide because a bare released binary happens to have both.

Two further corrections while checking it:

- **A deployed `zonai build` bundle is *not* in the gap.**
  `_bundlePublishedBinary` (`build.dart:230`) calls `writeMessageContractStamp`
  on the binary it bundles, precisely so the stock-binary deployment carries a
  contract. The uncovered case is narrower: the CLI used **in place**
  (`zonai serve`, `zonai db …`) — which is the developer's own loop, and so the
  place `zonai_schema` actually moves under them.
- No *contract* stamp is written for a released CLI, because it is built by a
  bare `dart compile exe` (`scripts.yaml:570`) rather than through
  `ProjectBinary.compile`. Two corrections to how this was written here
  originally, both established 2026-08-27: `compile.yml` contains no `dart
  compile exe` — it reaches that line through `sip run zonai compile` — and
  "nothing stamps a released CLI" is no longer true. That compile now bakes in
  `ZONAI_VM_HASH` and `ZONAI_DART_SDK` (`scripts.yaml:550`, via
  `tool/ci/vm_snapshot_defines.sh`), which guards a different hazard entirely:
  which VM snapshot format the host can load, so an `.aot` worker compiled by a
  skewed SDK is declined instead of killing the process with an uncatchable
  SIGABRT. See `docs/dart-sdk-skew.md`. The contract gap below is untouched by
  it.

So the guard gap is a separate item with a separate fix, and it has one now:
`Mailman._warnIfContractGuardInert` says the check is not running, once, at the
spawn where it would have run. Watched failing and watched staying quiet — the
three-row table is in `docs/stale-worker-guard.md`. It does not close the gap;
it stops the gap being silent, which was the actual complaint.

## Options

**(a) Accept it, and make the inertness visible.** **Done**, though for the
guard, not for linking — the two turned out to be unrelated (above). The
warning lives at the Mailman spawn sites rather than at startup: startup would
fire for `zonai version` and every other command that never spawns a worker,
where an inert guard costs nothing. Does nothing for dispatch cost or
fine-grained rate limiting, and never claimed to.

**(b) Ship zonai's sources inside the released binary and self-extract them.**
Nobody has weighed this, so it is written down rather than recommended. The
machinery already exists in a neighbouring form: the binary self-extracts
native libraries on first FFI use, with `native_library_stamp.dart` deciding
whether the copy on disk is the one this build should keep. The same shape
would give `zonaiPackageConfigPath()` something to find.

*The proposed killer — that this needs a populated pub cache and a `pub get` on
the user's machine — is false. Checked, not reasoned about.* `dart compile exe
--packages=<config>` does no resolution: it reads that file and nothing else.
Compiled and ran a binary from a directory with **no `pubspec.yaml`, no
`.dart_tool`, no `pub get` ever run in it**, against two packages copied out of
the pub cache into a scratch directory and named by a hand-written
`package_config.json`. It built and printed the right answers.

One detail that experiment surfaced, because it failed loudly first:
`languageVersion` per package is not optional and is not in the pubspec — it is
derived at resolution time. Getting it wrong fails at compile with a
field-promotion error pointing into somebody else's package, which reads as a
version-skew bug rather than a config bug. A vendored config has to carry it.

So the shape that could work is not "ship zonai's sources" — that dies
immediately, since `package:revali_router` and the other 56 would not resolve.
It is **vendor the whole closure and synthesise a config over it**, needing no
pub and no network. Measured on this machine (`dart pub deps` from
`apps/zonai`, sized against the workspace `package_config.json`):

- **58 packages**, **21.8 MB** of `lib/**.dart`, to embed and self-extract.
- The Dart SDK is *not* a new requirement: `zonai build` already shells out to
  `dart compile exe` (`project_binary.dart`), so a user without one cannot
  build today either.

What makes it a large promise is not the megabytes, it is what freezing that
closure into a release means. The merge already runs zonai-wins, so the app's
own code compiles against zonai's versions of every shared package — today
that is a short list (`equatable, meta, revali_core` against
`e2e/build_smoke`) because CLI and project resolved on the same machine at
similar times. A vendored closure baked into a release diverges from whatever
the project resolves, steadily, for as long as that release is in use, and
`logOverriddenPackages` would go from a three-name line to most of the graph.
That is the thing to weigh — not resolution, which works.

**(b) is still not recommended**, but for a different reason than the one
written here first: it is a real option with a real cost, not a dead end, and
its strongest argument (the guard) has been withdrawn.

**(c) Give the released binary its own contract stamp at CLI-build time.**
Closes the guard half only, not linking. Rejected in
`docs/stale-worker-guard.md` with reasons that still hold: one CLI serves many
projects, so a sidecar cannot describe any of them, and baking the hash in
converts `SchemaVersionCheck`'s deliberate "at or above the floor is fine" into
"identical or refuse". Listed so it is not rediscovered as an idea.

## Where this landed

**(a), and the linking residual stays open — accepted, not deferred.**

The reasoning changed on the way. (a) was recommended as a cheap consolation
while linking stayed unfixed; it turns out to be the *whole* fix for the thing
it addresses, because linking was never what made the guard inert. Closing
linking would leave the guard exactly as inert as it is now.

That leaves linking to be judged on its own merits, which are: in-process
dispatch (unmeasured) and fine-grained per-operation rate limiting (real, but
the rules layer still denies unregistered operations, so nothing is unsafe
without it). Against that, (b) costs a vendored 58-package closure that drifts
from the project's own resolution for the life of the release. **Not worth
closing at present.** Revisit if either the dispatch cost is measured and turns
out to matter, or a user hits per-operation rate limiting silently running
coarse.

## What CI cannot tell you here

Named in `build-fallback-next-steps.md`, repeated because it is the reason this
case keeps being verified by hand:

- `verify_build_command.sh` **cannot reproduce the bare-binary case.** It runs
  inside the repo, so zonai's sources are always reachable and pass 2 always
  links; pass 1 stands in for a bare binary with an env var, which is not the
  same thing.
- `e2e/build_smoke` depends on the monorepo's `libs/zonai_schema` by path, so
  both graphs agree and the `SQLiteDelegate` collision (issue #24) that forces
  the merge direction never arises. **Reversing the merge direction would stay
  green.** Only the manual proof against hosted `zonai_schema ^0.1.1` ever hit
  it.
- The same blindness applies to anything you build here. In this monorepo a
  project always links, which is also why the guard's snapshot path needed
  `ZONAI_FORCE_WORKERS=true` to be observed at all.

## How to verify whichever option is taken

The only honest test is outside this repo: a scratch project that depends on
`zonai_schema` from pub.dev, no `package:zonai` anywhere, driven by a
downloaded release binary rather than `dart run`. Confirm `resolveProjectLink`
skips (it logs its reason — every skip carries one, deliberately), then confirm
whatever the option promises.

For (a) specifically — and this is the one claim here that *was* checked, so
read what it was checked against. The stand-in is the compiled `.zonai/zonai`
in `apps/playground` with its `.contract` sidecar moved away, under
`ZONAI_FORCE_WORKERS=true`: that reproduces the state
`hostMessageContractHash` reads (compiled host, no stamp) beside stamped
workers, which is the same state a released binary is in. It does **not**
reproduce a released binary — nothing in this repo can — so what was proved is
that the warning fires on that state and stays quiet either side of it, not
that a downloaded `zonai` reaches it. The three rows are in
`docs/stale-worker-guard.md`. The remaining step is the scratch project above,
asserting the same line appears where it was never constructed by hand.

## Also worth knowing

- **Workers are still in every bundle.** `build()` calls `compile()`
  unconditionally before the link branch, and `db_config`/`db_crons` spawn as
  processes regardless — only operations and rules are ever registered
  in-process.
- **`todo.md`'s entry for this is stale** and should be rewritten to describe
  the bare-binary residual rather than the merge route. Whoever picks this up
  should fix that first, so the next reader does not re-plan work that shipped
  three releases ago.
