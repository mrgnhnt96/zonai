# Releasing

## Rule zero: never dispatch `Release` while `Verify Release` is failing

**If `verify-release.yml` is red for the commit you are about to release, you
do not have a release candidate. You have a bug. Fix it and start again.**

There is no version of "ship it anyway" that makes sense here. The point of
shipping is that the product works; a release that fails its own verification
is not early, it is wrong. Nothing about this repo's release is time-pressured
— `Release` is `workflow_dispatch` precisely so a human can take as long as
they need — so there is never a reason to walk past a red gate.

`verify-release.yml` triggers automatically on a successful `Compile`. It runs
without being asked, which means **the only way to skip it is to not look**.

This was written on 2026-08-13, after exactly that. Verify Release ran on
`fd0770c` at 22:09:35 and failed on three platforms — `TableMeta.get` not
found on macos-arm64 and linux-x64, and a backslash-separated package import
on Windows. `Release` was dispatched minutes later by someone who never opened
it. v0.6.3 went out with those bugs in it.

Before dispatching `Release`, check:

```sh
gh run list --workflow=verify-release.yml --limit 3 \
  --json conclusion,headSha --jq '.[] | "\(.conclusion)\t\(.headSha[0:8])"'
```

The newest run must be `success`, **and its SHA must be the commit you are
releasing**. A green run for a different commit tells you nothing.

### The exception, and what it costs to claim it

Some jobs here have **the previously released binary** as their subject rather
than the one being shipped. A defect that shipped in the *last* release fails
those forever, and shipping the fix is the only thing that can clear them.

Two are known, and the second was found the first time this exception was
claimed — the text below used to say `compat-check` was "the single job that
can be red for a reason the release does not own", and that was wrong:

- **`compat-check`** downloads the newest CLI release and `verify_compat.sh`
  Phase 1 runs it.
- **`cross-run-linux-x64`'s positive control.** Less obvious, because nothing
  about the job says "previous release": for a **cross-target** build the
  running binary cannot serve the target, so `zonai build` bundles a
  *published* one (`build.dart:218`), fetched at the version in the **project's**
  `zonai.yaml` — and `e2e/build_smoke/zonai.yaml` pins one. So the bundle under
  test carries a released binary, and any check reading a string that binary
  does not emit fails until a release ships one that does.

Do not assume the list is complete. Ask of any red job: *whose binary is it
actually running?*

Claiming the exception takes all four of these, checked and written into the
release notes. Anything less is Rule zero, and Rule zero has no exceptions:

Claiming the exception takes all four of these, checked and written into the
release notes. Anything less is Rule zero, and Rule zero has no exceptions:

1. **Every red job is one of the two above.** Anything else is about the
   candidate.
2. **The failure is in Phase 1**, i.e. attributed to the old binary. Phase 3
   is the new binary and is never excusable.
3. **No real consumer can reach it.** Say why in one sentence, from the
   constraint that protects them.
4. **This release clears it.** If the next release would fail the same way,
   nothing was fixed and this is not an exception, it is a habit.

**Claimed once, on 2026-08-13, for the 0.6.2 → 0.7.0 release.** All five
`compat-*` legs fail Phase 1 with `Member not found: 'TableMeta.get'` at
`.dart_tool/raindrop/schema_snapshot_runner.dart:32`. That file is the
**v0.6.2 binary's own** pre-migration raindrop_cli generator, emitted against
the `zonai_schema` in this tree, whose vendored raindrop no longer has
`TableMeta.get`. `apps/compat` depends on `zonai_schema` by `path:`, so Phase 1
pairs an old CLI with a schema no consumer of that CLI can resolve: v0.6.2
scaffolds a caret constraint from its own era, and `^0.1.x`/`^0.2.x` both
exclude `0.3.0`. The skew is the fixture's, not the field's.

`verify_compat.sh` already skips old-binary `compile`/`serve` for this exact
class of skew — its comment says the monorepo schema "may speak a newer IPC
than the previous release host" — and `db migrate generate` is the same
problem one step earlier, in a step the skip does not cover.

It clears itself: once v0.7.0 is the newest release, Phase 1 runs a
post-migration binary against a schema of its own era.

**`cross-run-linux-x64`, same release, same reasoning.** Its positive control
sabotages `.zonai/executables/db_rules.aot` and greps for the "would not spawn"
warning; the bundle answers `Loading dynamic library failed … file too short`
and falls back correctly, but emits no such warning. The warning landed in
`9d2433b` on 2026-08-12, and the bundle reports `Zonai: v0.6.1` — it is running
the released v0.6.1 binary, which cannot contain it. Bumping the fixture's pin
does not help: it would name v0.7.0, which is not published while it is being
verified, the same chicken-and-egg `cross_target_build.sh` already documents
for native libraries.

Be honest about what this costs, because it is more than compat's does. That
control exists because *"the silence just checked is compatible with a tap that
never fires"* — so while it is red, the job's own headline result (`rules and
operations answered, and neither fell back to its process`) is **unproven**
rather than merely unreported. This exception is being claimed over a real gap
in coverage, not over noise.

**Correction, written the moment v0.7.0 shipped: only compat self-clears.**
The claim above said both would, and that was wrong about `cross-run` — the
post-release `cross-run-linux-x64 (released)` failed identically, still
reporting `Zonai: v0.6.1`. Compat compares against *the newest release*, so it
moves on its own; `cross-run` reads a **hardcoded** version in
`e2e/build_smoke/zonai.yaml`, which tracks nothing and moves only when someone
moves it. "It self-clears" was reasoning by analogy from one gate to the other
without checking where each got its version, which is the same mistake as
assuming compat was the only such job in the first place.

`e2e/build_smoke` is pinned to 0.7.0 as of that release, whose binary does
carry the warning — a fix that did not exist until v0.7.0 was published, since
no earlier release contained it.

**If either is red on the next release, do not claim this a third time** — fix
the fixtures:

- Let `cross_target_build.sh` supply the target binary from the compile
  artifact instead of downloading a release, so the gate tests the candidate
  rather than whatever the fixture happens to name. This is the real fix: a
  pin bumped by hand each release is a step somebody forgets, and forgetting
  it is silent.
- Call `tool/ci/sync_playground_version.sh` from the release flow. It already
  takes a fixture directory and **nothing called it**, which is why
  `e2e/build_smoke`'s pin sat at 0.6.1 while the repo moved eleven versions
  past it.
- For compat, extend the Phase 1 skip, or give the fixture a published
  `zonai_schema` from the old binary's era.

Three artifacts ship from this repo, and they are **not** independent:

| Artifact       | Goes to  | Versioned by                    |
| -------------- | -------- | ------------------------------- |
| `zonai_schema` | pub.dev  | `libs/zonai_schema/pubspec.yaml` |
| `zonai_client` | pub.dev  | `libs/zonai_client/pubspec.yaml` |
| `zonai` (CLI)  | GitHub release | the `VERSION` file        |

## The coupling

The CLI declares a floor for `zonai_schema` — `kMinSchemaVersion`, in
`apps/zonai/lib/src/domain/schema_version/min_schema_version.dart`. Two things
follow from it, and **both** have to hold before the CLI ships:

1. **The floor must be published.** `zonai init` scaffolds
   `zonai_schema: ^<floor>` into new projects. A CLI released ahead of the
   schema it names hands people a pubspec pub cannot resolve.

2. **`zonai_client` must allow the floor — as published.** The client depends
   on `zonai_schema`. If the version of the client *on pub.dev* declares a
   constraint that excludes the floor, then anyone using both is pinned below
   it, no matter what this repo says. Widening the constraint here does nothing
   for them until the client is published.

Point 2 is the one that gets forgotten, because the repo looks correct while
consumers are stuck. It is real: `zonai_client` 0.1.1 declares
`zonai_schema: ^0.1.0`, which excludes `0.2.0`.

Neither is visible from the test suites. Every checkout here resolves
`zonai_schema` by `path:`, where the version check is a documented no-op, and
the constraints that bind consumers are the ones already on pub.dev — not the
ones in the working tree.

## The check

```
cd apps/zonai && dart run tool/verify_release_coupling.dart
```

Asks pub.dev whether a real consumer can actually reach the floor, and names
which of the two conditions is unmet. `release.yml` runs it before packaging,
so the CLI cannot go out ahead of its schema.

It is **expected to fail** between preparing a release and publishing — that is
the window it exists to describe.

It does *not* check that the floor is high enough. That is a human judgement
(see `kMinSchemaVersion`'s own docs); a floor left too low fails at the
consumer, not here.

## Order

1. **Publish `zonai_schema`.**
   Bump `libs/zonai_schema/pubspec.yaml`, add a `CHANGELOG.md` entry, then
   `cd libs/zonai_schema && dart pub publish`.

   If the release changes an API consumers implement, say so in the changelog
   with the migration — and if it changes anything a worker parses or dispatches,
   say that consumers must re-run `zonai compile`. A stale
   `.zonai/executables/*.exe` keeps the old code, and the `.protocol` stamp will
   not catch it: that stamp records the IPC *framing* version, not the message
   vocabulary.

2. **Publish `zonai_client`,** if its `zonai_schema` constraint changed — even
   when nothing else about it did. Without this step the widened constraint
   never reaches anyone.

   Prefer widening (`>=0.1.0 <0.3.0`) over bumping (`^0.2.0`) when the client
   does not touch what changed. A `^` pin drags the client's consumers onto one
   schema minor for no reason of its own.

3. **Raise `kMinSchemaVersion`** if this CLI now depends on something only the
   new schema has, and run the check above. It should pass once steps 1–2 have
   landed.

4. **Release the CLI.** Bump `VERSION`, then run the `Release` workflow.

## Raising the floor

Raise it in the same change that starts depending on newer schema — the CLI
generating code that calls an API added later, or sending an IPC message an
older schema cannot parse. `RateLimitOperation.custom` was exactly that: a
value the host sends and an old worker throws on.

Nothing enforces that pairing. The check above only asks whether the floor is
*reachable*, never whether it is *correct*.
