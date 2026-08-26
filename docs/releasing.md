# Releasing

## Rule zero: never dispatch `Release` while `Test` is failing

**If `Test` is red for the commit you are about to release, you do not have a
release candidate. You have a bug. Fix it and start again.**

`Test` carries the release verification: `verify-release.yml` is a reusable
workflow that `test.yml` calls (its `verify-release` job), so the five-platform
artifact matrix, the `zonai build` legs, the cross-target pair and the compat
check are all jobs inside the `Test` run. Before 2026-08-20 they were a
separate `Verify Release` workflow, and every reference below that says `Test`
used to say both.

There is no version of "ship it anyway" that makes sense here. The point of
shipping is that the product works; a release that fails its own verification
is not early, it is wrong. Nothing about this repo's release is time-pressured
— `Release` is `workflow_dispatch` precisely so a human can take as long as
they need — so there is never a reason to walk past a red gate.

`Test` triggers automatically on a successful `Compile`, and the verification
runs inside it. It runs without being asked, which means **the only way to skip
it is to not look**.

This was written on 2026-08-13, after exactly that. Verify Release ran on
`fd0770c` at 22:09:35 and failed on three platforms — `TableMeta.get` not
found on macos-arm64 and linux-x64, and a backslash-separated package import
on Windows. `Release` was dispatched minutes later by someone who never opened
it. v0.6.3 went out with those bugs in it.

Before dispatching `Release`, check:

```sh
gh run list --workflow=test.yml --limit 3 \
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

4. **Release the CLI.** Bump `VERSION`, **write the release summary**,
   regenerate the committed clients, then dispatch **`Compile`** — not
   `Release`.

   Bumping `VERSION` is what *makes* it a release. `resolve_release_version.sh`
   refuses unless `VERSION` is strictly greater than the latest CLI tag, so a
   `Compile` dispatched on `main` at any other time stops there instead of
   publishing. See **Dispatching Compile without releasing** below.

   ```sh
   echo "X.Y.Z" > VERSION
   # add a `## X.Y.Z` section at the TOP of RELEASE_NOTES.md -- see
   # "The release summary" below; `static` fails without it
   bash tool/ci/release_notes.sh check
   sip run version gen
   cd apps/playground \
     && UPDATE_GOLDENS=1 dart test test/gen_client_golden_test.dart \
     && UPDATE_GOLDENS=1 dart test test/doc_fixture_client_golden_test.dart
   ```

   The regeneration is not optional and nothing in the release flow does it for
   you: `zonai gen client` stamps the CLI version into every file it writes and
   into `generatorVersion`, and `apps/playground` commits that output as its
   golden baseline, so one line of `VERSION` invalidates 17 committed files.
   `sip run version gen` first, because `apps/zonai/lib/gen/version.dart` is
   gitignored and regenerating without it bakes the old version back in.
   `tool/ci/check_generated_client_version.sh` catches a miss in `static`,
   within seconds rather than a chain later.

   Then `gh workflow run compile.yml --ref main`, and **that is the whole
   thing** — Compile triggers `Test`, and `Test` finishing triggers `Release`,
   which publishes if the gate is green.

   **Expect exactly one `Release` run, and expect it to be green.** This
   changed on 2026-08-20. `Release` used to be triggered by *two* workflows —
   `Test` and the then-separate `Verify Release` — because it needs both to be
   green and a `workflow_run` trigger cannot say "whichever finishes last". The
   loser's attempt was refused as "the other one is still running", so every
   release carried one red `Release` run that meant nothing, and a red run that
   means nothing is what a red run that means *something* has to compete with.
   Merging the two removed the ambiguity: one prerequisite, one trigger, one
   attempt. If you see a red `Release` run now, read it — a refusal headed
   **"Refusing to publish"** names the gate that said no.

   A summary headed **"Waiting, not failing"** is still possible and still
   rare: it means the `Test` run that fired this attempt is already back in
   flight, which normally means somebody re-ran it. Wait for that run rather
   than re-running the `Release` attempt.

5. **Watch `Post-Release Verify`,** which fires by itself once `Release`
   succeeds.

   It is the half of the cross-target gate that cannot run before publication:
   `zonai build` fetches the native libraries from the release for *this*
   version, so `cross-build-linux-x64 (released)` and
   `cross-run-linux-x64 (released)` exercise the artifact people actually
   download rather than one assembled from compile artifacts.

   It is a **separate workflow** on purpose. These two jobs used to sit in
   `release.yml` as `needs: release`, where a failure painted the whole Release
   run red after the tag, the eleven assets and the `VERSION` commit had all
   landed correctly — "the release failed" when it had not. A green `Release`
   now means the version published; this workflow answers the other question.

   What the split does not change: it still runs **after** the release, so a
   regression here still means re-cutting a patch. Fix it, then
   `gh workflow run post-release-verify.yml --ref main` to re-check the same
   release without cutting a new one.

## The release summary

**Every release ships a short bulleted summary of what it contains, written by
hand into `RELEASE_NOTES.md` before the release is cut.** It is not optional and
it is not generated: `Release` refuses to publish a version this file does not
describe.

Until v0.8.5, what the workflow published was one line —

```
**Full Changelog**: https://github.com/mrgnhnt96/zonai/compare/v0.8.3...v0.8.4
```

— because `release.yml` passed `--generate-notes` and nothing else, and
generated notes on a repo that commits straight to `main` are a compare link.
That is a diff, not a summary.

The summary was never missing because nobody valued it: v0.7.0, v0.8.0 and
v0.8.1 all carry good hand-written highlights, added by editing the release
**after** it published. It was missing whenever somebody was busy. v0.8.2,
v0.8.3 and v0.8.4 went out with the bare compare link and stayed that way — and
v0.8.4 was the release that carried the whole API-tokens feature, the forced
password reset, `beforeSignUp`, dashboard push and `zonai ai update`. Its page
told anyone deciding whether to upgrade to go read ninety commits, most of which
are `test:` and `chore:`. The release page is the only place a consumer of the
CLI ever looks.

That is the shape of a step that lives only in a human's memory, and the reason
this one is a gate: a summary written before the tag exists cannot be the thing
that gets skipped when the release is the busy part.

### The shape

`RELEASE_NOTES.md` lives at the repo root and accumulates newest-first. One
`## X.Y.Z` heading per release — a human-readable tail is allowed, `## 0.9.0 --
the one with the tokens` names `0.9.0` — followed by bullets:

```markdown
## 0.8.5

- The dashboard's "Most sessions" list is clickable.
- Long tooltips stay inside the window.
```

Write for somebody deciding whether to upgrade: what they can now do, and what
stopped being broken. Group a multi-commit feature into one bullet and name it
in bold. Leave out anything whose whole audience is this repo — a refactor, a
test, a CI ceiling. Ten seconds of reading is the budget; the commit list is
already one click away.

### What enforces it

`tool/ci/release_notes.sh check` asserts that the **first** heading in the file
equals `VERSION` and that its section carries at least one bullet. It runs in
two places, on purpose:

- **`static`**, so it fails on the branch, in seconds. A `VERSION` bump that
  forgets the summary is caught next to the bump rather than a Compile and a
  Test later.
- **`release.yml`'s gate job**, before anything is packaged. Everything else in
  that file reaches the gate through `needs:`, so a refusal here skips the whole
  chain instead of failing beside a tag that already exists.

It reads the *first* heading rather than any matching one because the file
accumulates: a section for the version being released that sits below an older
one means the newest section was never written, which is the exact miss.

`tool/ci/release_notes.sh body v<X.Y.Z> <prev-tag> <owner/repo>` renders what
gets published — the section, then the compare link `--generate-notes` used to
be the only source of. `release.yml` runs it into `release-notes.txt`, echoes
the result into the job summary, and passes `--notes-file`. The body is built
by us rather than merged by `gh` so that what publishes is one behaviour,
testable on a laptop (`tool/ci/test_release_notes.sh`) and not a property of
whichever `gh` the runner happens to ship.

**What it cannot check, out loud:** whether the summary is *true*, or whether it
describes this version rather than the last one with the heading changed. It
checks that a human wrote something, bulleted, under the right number. The
judgement stays human; the gate only makes skipping it loud.

### Editing a description after the fact

The file is the source of truth going forward, but a published description can
be corrected — `gh release edit v<X.Y.Z> --notes-file <path>`. Do it from a
file, never an inline `--notes`, so the text is reviewable before it goes out.
v0.8.4's description was backfilled this way when this flow landed, from the
same `## 0.8.4` section that is still in `RELEASE_NOTES.md`.

## Dispatching `Compile` without releasing

Dispatching `Compile` on `main` is how a release is cut — Compile triggers
`Test`, and `Test` triggers `Release`. Nothing in the dispatch dialog says so,
and for a while nothing stopped it: `resolve_release_version.sh` used to bump
the latest tag's minor whenever `VERSION` was not ahead of it. Since the release
job commits `VERSION`, that is the state `main` sits in **from the moment a
release lands until someone bumps it again** — so anyone dispatching Compile to
"check CI" would have resolved a new minor and let the chain publish it.

Two changes closed that:

**`VERSION` must be ahead, or the resolver refuses.** No invented versions. The
refusal names both ways forward, because the person who hits it is usually one
dispatch away from a release they did not intend. It also leaves `VERSION`
alone on the way out.

**`Compile` takes a `dry_run` input.** Tick it to build against `VERSION` as it
stands:

```sh
gh workflow run compile.yml --ref main -f dry_run=true
```

The binaries carry the version already in `VERSION`, and the run is stamped
**Dry run** in its job summary so it is not mistaken for a release later.

A dry run cannot publish, and not because it is trusted to behave: `release.yml`
resolves the version **again, in its own checkout**, without the flag. So the
chain a dry run starts refuses at that second resolve. That independence is the
point — the two callers stamping `kVersion` and choosing the tag must never
disagree, and the way they disagreed before was `v0.6.3`, which published
binaries reporting `0.6.2`.

**The escape hatch.** `RELEASE_VERSION_ALLOW_BUMP=1` restores the old auto-bump.
Nothing sets it. It exists so that reverting this is a decision someone makes
deliberately, rather than a code edit made under time pressure — and so this
paragraph is where they find out it was a decision in the first place.

## Raising the floor

Raise it in the same change that starts depending on newer schema — the CLI
generating code that calls an API added later, or sending an IPC message an
older schema cannot parse. `RateLimitOperation.custom` was exactly that: a
value the host sends and an old worker throws on.

Nothing enforces that pairing. The check above only asks whether the floor is
*reachable*, never whether it is *correct*.

### Owed by OAuth and admin invites

The floor on this branch is `0.3.0` and is already too low. OAuth and admin
invites add `AuthType.oauth` and `RateLimitOperation.oauthStart` /
`.oauthCallback` / `.adminInvite` — vocabulary the host sends and an older
worker decodes with `Enum.values.byName`, which throws on a name it does not
have. Same failure as `RateLimitOperation.custom`.

That makes the next schema release a `0.4.0`, and `0.4.0` is exactly what the
**published** `zonai_client` excludes: it declares `zonai_schema: ">=0.1.0
<0.4.0"`. So steps 1–3 above are all load-bearing here, and step 2 is not
optional even though `zonai_client` itself does not touch OAuth.

Half of this is self-enforcing and half is not, which is worth knowing before
you rely on the wrong half:

- Bumping the schema to `0.4.0` without widening the constraint **in this
  repo** fails at `dart pub get` in the root — it is a pub workspace, so
  version solving refuses. You cannot miss it.
- Widening it here and not publishing `zonai_client` fails **nowhere local**.
  The repo resolves happily; consumers who use both packages simply cannot
  upgrade. Only `verify_release_coupling.dart`, which reads pub.dev, sees it.
