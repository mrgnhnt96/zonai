# Next session — the release gate is in, and streaming is dead

**READ THIS FIRST: `stream-zero-bytes`.** All three streaming routes return 200
and headers and then **zero body bytes**. Reproduced independently on merged
trunk, on both worker transports. Every real consumer of those routes is
starved, not slow. It is filed, briefed, and a Crawler is on it — see
[The streaming bug](#the-streaming-bug).


Written 2026-08-14 (second session that day). Everything below is committed,
merged and green on trunk.

**`release-gate` landed.** It was held for maintainer review, reviewed, and
merged on the maintainer's instruction to decide it myself. The single largest
risk reduction in `docs/testing-strategy.md` is now in place: `release.yml`
cannot publish without green `Test` and `Verify Release` runs **for that exact
SHA**. See [The release gate](#the-release-gate) for what it does and the three
judgement calls baked into it.

## What shipped

| Commit | What |
| --- | --- |
| `6a4293e` | **`release-gate`** — `release.yml` refuses to publish without green `Test` and `Verify Release` for that exact SHA |
| `ca6e8bd` | **`ci-static-resolve`** — the static job resolves the out-of-workspace packages before analyzing them |
| `4beb750` | **`ratelimit-500`** — the bucket read-then-write is serialized on the writer |
| `38f9ace` | The concurrency assertion's `actual`/`expected` formats now match — it could never pass |
| `95b5339` | What actually serializes that bucket, and how far the guarantee reaches |
| `1dde68c` | The e2e CI job is live, and is the only real gate on the e2e driver |

Merges: `919a2ae`, `41d7e3f`, `e0860ef`. All three integrated through
`showrunner integrate`, with checks re-run on the **merged** result, not the
branch — then each fix's own consumer exercised against merged trunk, because
the harness is right that a branch proof does not transfer.

## Corrections to the previous handoff

The last handoff got two things wrong, and both were load-bearing. They are
corrected here rather than in place, because the wrong version had already been
copied into briefs and into showrunner's own config.

**"Analyzer excludes do not cross a nested package boundary" is FALSE.** The
previous session concluded this after an attempt that did not work, and stated it
emphatically enough that it was passed on as settled. A Crawler refuted it, and
it was then re-measured independently:

```
e2e/*/.dart_tool deleted, no exclude:   168 errors, all under e2e/
same tree, `- "e2e/**"` added to root:    0 errors  (62 issues, all pre-existing infos)
```

A root `analysis_options.yaml` exclude **does** suppress a nested package that
has its own `pubspec.yaml`. The corollary the last handoff drew — that the
existing `stress/fixture/**` exclude "is therefore also doing nothing" — is wrong
the other way: deleting that line takes `dart analyze .` from 288 to 329 issues.
**It is load-bearing.** Excluding was therefore a real option for
`ci-static-resolve`; it was rejected on merit (it would silently stop analysing
the fixture code `build_smoke` and `crud_matrix` exist to model), not on
capability.

**The out-of-workspace package set is nine, not seven.** `apps/*` in the root
workspace is a *shallow* glob, so `apps/zonai/tool/native/argon2_builder` is
outside the workspace too — it was the last 2 of the 226 errors a clean tree
reports. `stress/fixture` is the ninth, and it is now resolvable (below), so the
`test static` loop covers it too.

Both wrong claims were also sitting in `.showrunner/config.json`'s `resolve`
check as its stated rationale. That copy has been corrected, and the check now
resolves `argon2_builder` too.

**And a correction to this session's own brief.** `e2e-full-surface` was told
by-id variants were "the highest-value gap", naming `@Get(':id')`, `@Patch(':id')`,
`@Delete(':id')` and `@Delete('all')`. It re-derived the routes from source and
refuted that: **`db_controller` has no `:id` route at all** — get, patch and
delete all take a where clause, not a path param. Those routes belong to
`PhotosController` (`/img/:id`, binary blob storage with ownership row rules) and
to `AuthController.logoutAll`. The real count is **~38 declared routes, not ~32**.
The gap was real; the description of it was not.

## The release gate

**Merged (`6a4293e`, +538 lines).** The premise held at source: `release.yml` was
`workflow_dispatch:` only with its `workflow_run: [Verify Release]` trigger
commented out, so verification ran beside publication.

It adds `tool/ci/check_release_gates.sh` (queries the runs API by `head_sha`,
refuses unless the latest `Test` and `Verify Release` runs for that exact commit
succeeded on the default branch), a `release-gate` job every other job reaches
through `needs:`, the uncommented auto trigger, and a `force: true` dispatch
input recorded in the job summary.

Verified independently, not taken on report:

```
check_release_gates.sh: 12 checks passed (11 of them refusals)
check_workflows.sh: ok: every release.yml job is gated behind `release-gate`
```

The refusals run against a stubbed `gh`: absent run, red run, in-flight run,
another commit's green runs, an older green behind a newer red, non-default
branch, `force` off the dispatch path, non-sha. Three mutations of the script
under test were each caught. No release was cut, dispatched or tagged.

**Three judgement calls, reviewed and kept.** Each was flagged by the Crawler as
a deliberate deviation; each was checked against the workflow triggers before
merging, and none is hard to undo:

1. It added a **default-branch check the plan did not ask for**, reasoning that
   uncommenting the auto trigger means a `Compile` dispatched on a feature branch
   would otherwise walk the chain to publication. `force`-overridable, ~10 lines
   to delete.
2. **`force` is honoured only when a gate is not green**, so an ordinary dispatch
   of a green commit needs nothing — deliberately, so `force` does not become
   habitual.
3. **`release.yml`'s own `chore: release vX` commit is pushed with
   `GITHUB_TOKEN`, which starts no workflow runs.** So that commit has no `Test`
   run, and a release dispatched on it with nothing pushed since is *correctly
   refused*. This is a real operational consequence for the next release, not
   just a code detail.

**Why the default-branch check is right, verified rather than assumed.**
`compile.yml` is `workflow_dispatch:` **only**, and `verify-release.yml` triggers
on `workflow_run: [Compile]`. So the whole release chain starts with a human
dispatching Compile — and a Compile dispatched on a feature branch would, with
the auto trigger restored, walk all the way to publication. The branch check is
what closes that. `test.yml` triggers on `push: branches: [main]`, so a main
commit does have a `Test` run and the gate is satisfiable in normal operation.

`verify.yaml` rules for both scripts are applied. Re-proven on merged trunk:
`check_release_gates.sh: 12 checks passed (11 of them refusals)` and `ok: every
release.yml job is gated behind release-gate`.

## The streaming bug

Found by `e2e-full-surface` while adding coverage — nobody was looking for it.
This is the most severe thing the e2e layer has surfaced, worse than
`ratelimit-500`, because a 500 at least tells the caller something happened.

`GET /db/stream` returns 200 and the response headers, then **zero body bytes for
35 seconds across three mutations to the exact row being watched** — not even the
initial snapshot that `stream_one.dart` reads before entering its `await for`
loop. The server log prints `Streaming query: ...`, so the subscription *is*
established, but never `Stream completed` and never an error.

**A second, distinct defect hides behind the same symptom.**
`/db/stream/list` throws an uncaught `type 'Null' is not a subtype of type
'Map<String, dynamic>'` server-side, visible only in the server log — over HTTP
the connection just hangs identically. One symptom, two bugs.

**Why it is worse than a leak.** `zonai_client`'s generated
`db_data_source_impl.dart` assumes exactly one JSON value per received chunk with
no cross-chunk buffering. If the server never flushes a chunk, every consumer is
**starved** — and cannot distinguish that from a stream that simply has nothing
to say.

Reproduced by the orchestrator on merged trunk (`7590eaa`, freshly compiled
binary): all three routes report `no event within 8s (0 bytes past the response
headers)` on **both** transports, with the other 16 fixture legs green. So it is
neither environment- nor transport-specific.

Covered by `knownFailure()` in `tool/ci/e2e/drive.dart::_streaming` — reports
every run, gates nothing. **The test is shaped so a partial fix cannot fake a
pass:** it mutates the watched row *before* checking for the initial snapshot, so
delivering only the initial value still fails.

**The blocker is a decision, not a diagnosis.** Does `/db/stream` emit an initial
snapshot on subscribe, or only deltas? Flush per event or per batch? A fix that
makes the assertion pass without that being decided deliberately is how this
comes back. The leaf says so, and says that closing with a precise diagnosis and
the semantics question named is a good outcome.

## The rate-limiter fix, and how far its guarantee actually reaches

`RateLimiter.check`'s one-shot insert-conflict retry is gone; the whole
select-then-insert-or-update runs in `db.transaction`. Proven both directions:

```
without the fix:  21 of 24 creates and 1 of 8 reads answered 5xx   <- matches the original incident exactly
with the fix:     0 of 32, on BOTH worker transports, seed and verify phases
```

Re-proven against **merged trunk** with a freshly compiled binary, not just on
the branch — `e2e layer passed.`, both legs.

**Read this before touching that code.** The fix's original comment credited
`db.transaction` with the guarantee. Traced to source, the real chain is:

- `libs/resqlite/lib/src/database.dart:455` — `Database.transaction` is
  `writer.locked(() => writer.transaction(body))`, so the mutex spans
  BEGIN → body → COMMIT, not each statement
- `libs/resqlite/lib/src/writer/writer.dart:17-26` — that mutex is documented
  FIFO-fair
- `libs/resqlite/lib/src/writer/write_worker.dart:54` — `BEGIN IMMEDIATE`, not
  DEFERRED
- `apps/zonai/lib/src/deps/zonai_db.dart:9` — `_db` is a **top-level static**,
  and those are **per-isolate** in Dart, not per-process

So the guarantee is **per-isolate**. It holds today only because the sole
`Isolate.spawn*` in `apps/zonai` is `mailman.dart:689`, which spawns db *workers*
(ops/rules), never a second request handler. Give the server a second isolate for
throughput, or let a worker open its own `ZonaiDb` and touch `_rate_limit`, and
there are two writers with two mutexes contending at the SQLite level — where
`BEGIN IMMEDIATE` returns `SQLITE_BUSY` rather than queueing, and the 500 comes
back wearing a different hat. A retry loop would not save it; the fix then is one
writer, or an atomic upsert. This is written into the code comment too.

## What is still broken

**`libs/resqlite` is 55/172.** Unchanged. Most of its test files never call their
own `setUpResqliteNative()` helper — an undeclared prerequisite inside resqlite's
own suite, not fixable from `scripts.yaml`.

**`stress/fixture` resolves now** (`stress-pub-graph`, merged `5b97344`). Two
`dependency_overrides` were needed, not one: `raindrop`, because
`zonai → raindrop_cli → raindrop ^0.0.1` is satisfiable only by the workspace's
own path entry and is not published; and `zonai_schema`, because
`zonai → zonai_web → zonai_client` pulls a *hosted* `zonai_schema` range that
collides with the fixture's own path dep once outside the workspace. Both are
mirrored into `harness_setup.dart`'s generated `pubspec_overrides.yaml`, which
**replaces** `pubspec.yaml`'s `dependency_overrides` wholesale rather than merging
— confirmed by testing, and the reason a single-sided fix looks right and fails.

Proven from a genuinely clean state on merged trunk: `.dart_tool`, lock and
overrides deleted, `dart pub get` exits 0.

**`stress/`'s server still will not start**, on a pre-existing and unrelated
defect the Crawler declined to touch: the local dev revali checkout's
`revali_client` `HttpInterceptor` API has moved ahead of what
`apps/web/lib/api/api_client.dart` and `libs/zonai_client/lib/src/utils/interceptor.dart`
implement (`FutureOr<HttpResponse?>` vs `void`). The harness gets through pub get,
migration generate+apply and `zonai compile` before hitting it. Not a pub-graph
problem; worth its own leaf if anyone needs the stress harness end to end.

**`analysis_options.yaml` still excludes `stress/fixture/**`.** Removing it is
verified safe (`dart analyze .` exits 0, zero issues under `stress/fixture`) but
was not done, so it is a one-line follow-up rather than a question.

## What is left

**In flight as this was written:** `stream-zero-bytes`, alone and deliberately so
— the bug is about delivery *timing*, and a loaded machine makes "no bytes for 8s"
ambiguous.

Still ready, in rough priority:

1. **`e2e-crud-matrix`** — serialized (`native-build`). The fixture now carries
   real custom-operation coverage, so this is narrower than when it was written.
2. **`process-identity`** — a running zonai process cannot say which project it
   belongs to. Still true and still costs time on every port conflict: the only
   `claude -p` Crawler on the box mid-session belonged to another repo and could
   be told apart only by the brief text in its command line.
3. **`test-load-fragility`** — serialized. Confirmed live again this session:
   integration had to be held twice while load average sat at 20.
4. `stress-thresholds` (newly unblocked by `stress-pub-graph`) · `revali-core-bump`

**And the thing that is not a leaf: CI has still never run.** Every gate added
over these two sessions — `test.yml`, the static job, and now `release-gate` —
is proven from a local tree and has **never executed on a real runner**. The
release gate in particular has been proven only against a stubbed `gh`. That is
the next thing to *observe* rather than infer, and it needs a push, not a
Crawler.

## Traps worth not rediscovering

New this session, and the first three cost real work:

- **`verify.yaml`'s runner is not a YAML-aware shell.** Three failed attempts to
  write one rule. It strips a *surrounding* double quote but does **not** unescape
  what is inside, so `cd \"$d\"` reaches `sh` with literal quote characters in the
  path. A **single**-quoted scalar keeps its quotes and gets exec'd as one
  filename (`No such file or directory` naming the entire command). A `- |` block
  scalar arrives as the literal string `|` and dies on a shell syntax error that
  reads like a broken check rather than a malformed rule. **Write commands
  double-quoted with no inner quotes at all.**
- **Two Crawlers can independently produce the same fix and conflict on it.**
  `check_verify_exemptions.sh` was corrected by `e2e-full-surface` and by the
  orchestrator within the hour, because the misclassification blocked every commit
  to every gated path tree-wide and so was hit from two unrelated directions.
  Resolve by hand, then `showrunner integration-commit --crawler <name>` **and**
  `game_loop attribute --merge <ref>` — the second is what stops the harness
  reporting a sibling's files as unexplained. Order matters: attribute *after* the
  branch has its commit, since attribution is recomputed from the ref.
- **`showrunner close --proof` resolves relative paths against the MAIN checkout,
  not the worktree.** A Crawler passing a relative path gets its staleness check
  run against the main checkout's older, unrelated copy of that file, and is
  refused with a confusing timestamp mismatch. Pass an absolute path.
- **An exemption marker written to silence a false positive is worse than no
  marker.** `check_verify_exemptions.sh` classed `dart pub get` as analyze-only,
  because its `REAL` whitelist omitted it — so a rule that resolves a real
  dependency graph was told to justify itself as a downgrade. The fix was to
  correct the classifier, not to write `RECHECK never` on a check that is real.
  Its own comment says it is tuned to avoid exactly this ("a false *exempt* is
  noise on a rule that is fine, and noise is what gets a check ignored").
- **A `claude -p` Crawler cannot be resumed.** One ended its turn with *"Rebuild
  is running in the background. I'll continue as soon as it completes"* — and
  died there, with uncommitted work in its worktree and a stale claim that
  `reap --apply` would have handed to a second orchestrator. Its work was
  rescued as `4beb750` and the leaf re-spawned based on that commit. **Every
  brief now carries a standing finding: run long commands in the foreground,
  and commit as you go.**
- **`showrunner spawn --dry-run` is not side-effect-free.** It creates the
  worktree, populates submodules, writes the brief and *claims the leaf* — only
  the launch is skipped. Recovering means `release`, `git worktree remove`, and
  deleting the branch before the real spawn.
- **An assertion can be a guaranteed red and look like a gate.** Flipping the
  concurrency `knownFailure()` to a real `expect()` left `actual` formatted as
  `"N of 24 creates and M of 8 reads answered 5xx"` against
  `expected: "0 of 32 answered 5xx"`. Those strings can never compare equal.
  `dart analyze` cannot see it; only running it can. This is why the local
  `.game_loop` rule for `tool/ci/e2e/**` is a syntax floor and **CI's `e2e` job
  is the gate that matters** — the two are one decision, and `test.yml` now says
  so.
- **Cross-session mail cannot reach a headless Crawler.** `SendMessage` to a
  `claude -p` session is held for the recipient user's approval, and there is no
  user there to approve it. It expires undelivered. Everything a Crawler needs
  must be in its brief at spawn time, via `--finding`.
- **`integrate` refuses on harness-rules drift even when the drift is yours.**
  Adding `verify.yaml` rules in the main checkout after spawning makes every
  in-flight worktree drift. Copy `.game_loop/verify.yaml` into each worktree,
  then actually run the obligations the new rules create — a synced file that
  was never exercised satisfies the check and proves nothing.
- **`integrate --only` takes a leaf id, not a branch name.** `--only
  showrunner/ci-static-resolve` prints *"nothing to integrate"* rather than an
  error, which reads exactly like success.
- **`run_e2e.sh` takes `[binary] [fixture...]`.** Passing a fixture name first
  makes it look for a binary by that name. It needs a compiled binary:
  `sip run zonai compile` first, or `ZONAI_E2E_BINARY=`.
- **`baseline.json` records no SHA**, only `checks` and `ts`. A stale baseline is
  therefore an unidentifiable comparison point. Re-take it on a quiet machine
  before integrating — and never under load, or it records spurious failures as
  expected.

Carried forward, still true:

- **The compiled/e2e tests abort under machine load** and it looks like a code
  regression, not flakiness. Signature: several suites reporting
  `(setUpAll) - did not complete` at one timestamp. Re-run alone before believing
  it. `test-load-fragility`.
- **`ZONAI_FORCE_WORKERS` is not the axis** that separates the transport bugs.
  The real axis is `ZONAI_WORKER_TRANSPORT=process|isolate`.
- **The e2e fixtures resolve `zonai_schema` by path, not from pub.dev**, so the
  "worker compiles its own *published* serializer" half of `02cfcef` is still
  unreachable by the e2e layer.
- **`.game_loop/verify.yaml` is gitignored, so it cannot ride a branch.** Crawlers
  propose rules in their close reason; the orchestrator applies them by hand.
- **An attached database inherits nothing** — not the journal mode, not pragmas,
  not the second connection.
- **A `wal_checkpoint` against a non-WAL database is not an error.** It succeeds
  and does nothing.
- **`PRAGMA` is not a read verb**, so `ResqliteDelegate.execute` routes it to the
  writer, which discards row data. Read it back through `transaction`.
- **`min` resolves to raindrop's SQL aggregate, not `dart:math`'s.**
- **This is a shared worktree.** Other sessions commit here concurrently. Commit
  with an explicit pathspec.

## Driving the campaign

showrunner is at `./.showrunner/bin/showrunner` (project-local, **not** global).

```
./.showrunner/bin/showrunner status
./.showrunner/bin/showrunner ready
./.showrunner/bin/showrunner spawn <leaf> --actor <you> --launch --finding "..."
./.showrunner/bin/showrunner integrate --only <leaf-id>
```

Both local patches in `.showrunner/PATCHES.md` are **still applied** — verified
this session: `post_inject` (6 hits in `worktree.py`), `adopt_pid` (2 in
`graph.py`, 2 in `cli.py`). Claims recorded the launched sessions, not the spawn
processes. Re-running `install.sh` silently drops both.

**Crawlers cannot resolve the bare `showrunner` command** — `.showrunner` is
gitignored and absent from a worktree. Every brief must give the absolute path
`/Users/morgan/Development/dart_projects/zonai/.showrunner/bin/showrunner`. This
is now a standing `--finding`; two of eleven leaves in the previous run were
closed by the orchestrator because of it.
