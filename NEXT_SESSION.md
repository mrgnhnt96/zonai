# Next session — the test strategy, and what it has already caught

Written 2026-08-14. HEAD is **24 commits past `v0.7.1`** (15 substantive, 8 merges
from the parallel-agent campaign). Everything below is committed and green unless
it says otherwise.

Suites now: **apps/zonai 504 · zonai_schema 251 · apps/web 145 · zonai_logger 46 ·
apps/docs 19 · playground 5 · zonai_client 4 · apps/server 3** (977 in-repo), plus
**raindrop 755** across five packages, which nobody had ever run. `libs/resqlite`
is 55/172 and that is real — see [What is still broken](#what-is-still-broken).

The previous handoff's release blocker is **resolved**: `a6160b9`, `df76021`,
`1854c1d` and `3bcae06` all shipped in `v0.7.1`. Its "Traps worth not
rediscovering" section is carried forward at the bottom of this file.

## What was wrong

The last release was bumpy, and the reason was structural rather than any one bug.

**CI ran no tests.** Six workflows existed. Exactly one `dart test` invocation
appeared in any of them, in `deploy-docs.yml`, scoped to `apps/docs`. The
504-test suite covering the actual product had never executed on CI hardware, and
had never executed on Windows at all — a release target.

**The release gate was inverted.** `verify-release.yml` triggers on `Compile`
completing; `release.yml` is `workflow_dispatch:` only, with its
`workflow_run: [Verify Release]` trigger commented out. Verification ran *beside*
publication, not before it, and nothing stopped a human dispatching a release over
a red or absent verify run.

**No static gate could be turned on.** `dart analyze .` reported 7,129 issues —
6,744 errors, *all* from `apps/web/build/`, Jaspr output that nothing excluded.
Zero real errors hid behind that wall.

**There was no test entrypoint at all.** `scripts.yaml` had `bootstrap`, `compile`
and `gen` targets for everything and no `test` key. Every suite was invoked by
hand, with prerequisites recorded only in `verify.yaml` comments.

**And the local gate had gone stale.** Six `verify.yaml` rules were downgraded from
real tests to `dart analyze` because the real check "fails locally for pre-existing
reasons". Each was true when written. Nothing re-asked. Re-measured on 02cfcef:
**all six pass**.

## What shipped

| Commit | What |
| --- | --- |
| `96f2710` | Root `analysis_options.yaml`; `dart analyze .` exits 0 (was 3) |
| `3f9bd2f` | **Exemptions now expire** — `RECHECK <date>`, 180-day cap, self-policing |
| `113413e` | Revert an unintended `revali_core` 2.0.0→3.0.0 major bump |
| `3d2b953` | Regenerate the stale committed docs search index |
| `b365aa4` | `libs/zonai_logger`'s first suite — 46 tests, all mutation-tested |
| `39db4e5` | `libs/zonai_client`'s first suite — export surface + web-safety split |
| `b626583` | Track `docs/testing-strategy.md`; ignore `.showrunner` / `.worktrees` |
| `3d7a43f` | `todo.md`: zonai processes cannot be attributed to a project |
| `6bca048` | **`scripts.yaml` gains `test`** — static / unit / cli / e2e / submodules |
| `ce9cf26` | `test docs` split out, because its suite skips itself without a build |
| `eafecd5` | **`test.yml`** — the first CI job that runs zonai's tests, on 3 platforms |
| `1da4c84` | The two constraints the e2e layer has to satisfy |
| `bdaa61d` | **The e2e layer** — `run_e2e.sh` + `drive.dart` + `crud_matrix` fixture |
| `8dc4922` | `dart format` the 155 human-written files that had drifted |
| `8f584b3` | Format what humans write, not everything the walker finds |

`docs/testing-strategy.md` is the plan all of this executes, measured against
`02cfcef` rather than reasoned about.

## What it has already caught

This is the part worth reading — the point of the investment is what it finds.

- **A live product bug.** Under concurrent creates, **21 of 24 requests answer
  HTTP 500** — `RateLimiter._consume` retries a conflicting insert exactly once,
  which is not enough under real concurrency. A rate limiter that fails with a 500
  instead of a 429 tells the caller nothing about backing off. Filed as
  `ratelimit-500`. Found by the e2e layer on its **first run**.
- **A test that was not running at all.** Two duplicate top-level keys in
  `verify.yaml`; the file parses to a dict, so the later entry silently won —
  `ai_templates_test.dart` had not been running from that rule.
- **755 raindrop tests nobody had ever executed**, all passing. This also refuted
  a caveat I had written into the brief: `raindrop_postgres` does **not** need a
  live Postgres service; its tests are mocked.
- **A CI job that would have failed on its first run** — see below.
- **A suite that reported green by not running.** `apps/docs`' `anchors` test calls
  `markTestSkipped` when `build/jaspr` is absent, so `dart test` there returned
  three different answers depending on local state: skipped (green) with no build,
  failed against a stale one, passed against a fresh one. Now `test docs`, which
  builds first: 19/19 where the bare command gave 18 + 1 skip.

## What is still broken

**`ci-static-resolve` — CI's `static` job fails on a clean runner.** Not fixed.
`dart analyze .` walks into `e2e/*` and `stress/`, which sit outside the pub
workspace on purpose; the job only runs a root `dart pub get`, so on a fresh
runner none of them resolve and every import reads as broken. Measured twice: a
new fixture produced 46 unresolved-import errors that `dart pub get` inside it
dropped to "No issues found!" with no source change, and separately `stress/` and
`e2e/external_auth` lost their `.dart_tool` mid-session and put 74 errors into a
root analyze that had been exit 0 minutes earlier.

> **Do not try to fix this with `analysis_options.yaml` excludes.** I did; it does
> not work and was reverted. Analyzer excludes do **not** cross a nested package
> boundary — a directory with its own `pubspec.yaml` forms its own analysis
> context. The existing `stress/fixture/**` exclude in that file is therefore also
> doing nothing, and its comment should be corrected rather than trusted.

`.showrunner`'s own `resolve` check has been changed to `dart pub get` in `e2e/*/`
and `stress/` for this reason. Keep the CI job consistent with it, or say why not.

**`libs/resqlite` is 55/172.** Real, and unchanged. Most of its test files never
call their own `setUpResqliteNative()` helper — an undeclared prerequisite inside
resqlite's own suite, not fixable from `scripts.yaml`.

**`stress/fixture` cannot resolve from a clean checkout** (`stress-pub-graph`). It
path-depends on `apps/zonai`, which declares `resolution: workspace`; a workspace
member cannot be path-depended-on from outside its workspace.

## What is left

Nothing is running. Nine leaves are ready, in rough priority:

1. **`release-gate`** — the actual goal, and now unblocked. Make `release.yml`
   refuse to publish unless `Test` and `Verify Release` are green **for that exact
   SHA**. Query the checks API; do not trust `workflow_run` ordering — that is what
   produced the bug. **The maintainer asked to review this one before it lands.**
   The hard part is proving it can *refuse*, not that it can pass.
2. **`ratelimit-500`** — the live bug above.
3. **`ci-static-resolve`** — CI is red on a clean runner until this lands.
4. **`e2e-full-surface`** — the e2e layer drives **6 paths**; zonai declares about
   **32 routes**. All four verbs are covered, so this is a route gap, not a verb
   gap. Missing: by-id variants (`GET/PATCH/DELETE :id`, `DELETE all`), custom
   operations, all three streaming routes, auth beyond sign-in/sign-up, and
   health/metrics/run.
5. `e2e-crud-matrix` · `test-load-fragility` · `process-identity` ·
   `revali-core-bump`

## Traps worth not rediscovering

New this session:

- **A conditional skip is a silent pass.** `markTestSkipped` on a missing local
  artifact means the test never runs in CI and reports green forever. Treat any
  skip in a gating suite as a failure until proven otherwise.
- **`dart analyze .` and `dart format .` both walk into places you do not own** —
  nested packages that are not resolved, tracked generated code, and the two
  submodules, which are *separate git repos*. Drive both off `git ls-files` instead.
- **A branch that is green is not a trunk that is green.** Happened twice, and
  showrunner refuses the merge for exactly this reason. Both times the branch was
  fine and the trunk had different local state.
- **The compiled/e2e tests abort under machine load** and it does not look like
  flakiness — it looks like a code regression. Signature: several suites reporting
  `(setUpAll) - did not complete` at one timestamp. 504/504 in isolation, mass
  abort at 1m14s under load. Re-run alone before believing it. `test-load-fragility`.
- **`ZONAI_FORCE_WORKERS` is not the axis that separates the transport bugs.** I
  briefed a Crawler to use it and was wrong. For `e2e/*` it is the same
  configuration twice. The real axis is `ZONAI_WORKER_TRANSPORT=process|isolate`;
  `isolate` is the leg where `551081f` and `02cfcef` actually fail. `run_e2e.sh`'s
  header explains it.
- **The e2e fixtures resolve `zonai_schema` by path, not from pub.dev.** So the
  "worker compiles its own *published* copy of the serializer" half of `02cfcef` is
  still unreachable by the e2e layer. Declared, not closed.
- **`.game_loop/verify.yaml` is gitignored, so it cannot ride a branch.** Crawlers
  are told to propose rules in their close reason; the orchestrator applies them by
  hand. `integrate` refuses a branch whose rules drifted, which is what makes the
  instruction safe.

Carried forward from the previous handoff, still true:

- **An attached database inherits nothing** — not the journal mode, not pragmas,
  not the second connection. Apply per connection *and* per schema.
- **A `wal_checkpoint` against a non-WAL database is not an error.** It returns
  successfully and does nothing.
- **`PRAGMA` is not a read verb**, so `ResqliteDelegate.execute` routes it to the
  writer, which discards row data. Read it back through `transaction`.
- **`min` resolves to raindrop's SQL aggregate, not `dart:math`'s.**
- **Two connections, one file.** Anything connection-local must be applied to both.
- **This is a shared worktree.** Other sessions commit here concurrently; HEAD moved
  several times mid-session. Commit with an explicit pathspec.

## Driving the campaign

showrunner is installed at `./.showrunner/bin/showrunner` (project-local, **not** a
global command; `.showrunner` and `.worktrees` are gitignored).

```
./.showrunner/bin/showrunner status        # what is ready, claimed, done
./.showrunner/bin/showrunner ready         # unblocked and unclaimed
./.showrunner/bin/showrunner spawn <leaf> --actor <you> --launch
./.showrunner/bin/showrunner integrate     # serial merge, checks on the MERGED result
```

Two things that will bite:

- **`.showrunner/PATCHES.md`** records two local patches to the installed copy —
  a `post_inject` hook (submodules do not populate in a worktree, and
  `apps/zonai/pubspec.yaml` path-depends on both) and an `adopt_pid` fix (a
  `--launch`ed Crawler's claim named the spawn process, so `reap --apply` would
  hand a live Crawler's leaf back to `ready` without stopping it). **Re-running
  `install.sh` silently drops both.** The grep commands to check are in that file.
- **Crawlers cannot close their own leaves** unless the brief gives an absolute
  path — `.showrunner/bin/showrunner` is gitignored and absent from a worktree.
  Two of eleven leaves hit this and were closed by the orchestrator.
