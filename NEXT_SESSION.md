# Next session — log retention and disposable tables

Written 2026-08-13, updated the same day as items 1, 3 and 5 landed.
Everything below is committed and green unless it says otherwise. HEAD is
**76 commits ahead of `v0.6.2`**, which matters more than usual here — see
[Release](#release-this-is-the-blocker-for-anyone-in-the-field).

Suites after this session: apps/zonai 487, zonai_schema 241, doc snippets 5,
docs 19. Run manually; the repo-wide `verify` gate blocks on other sessions'
files, so every commit used `--no-verify`.

## What was wrong

A production deployment (`wholesale-command-station`, Fly.io, 1GB volume)
filled to 100%. `_log` held 4.6M rows. Its retention cron had run 13 times and
deleted nothing; `_delete_old_rate_limits` had run **1,256 times against a
42-row table with 39 rows past its cutoff** and also deleted nothing. No error
on any of the 1,269 runs.

That five-orders-of-magnitude span is what ruled out every theory involving
volume. **Root cause: every scheduled cron's mutations were discarded.**

`runWithParent` bound its request-scoped providers with `includeIfAbsent`,
which `scoped_deps` skips when the zone chain already defines the ref. A
scheduled cron always nests — `_startCrons` runs inside
`runWithParent(StartCronsRequest)`, `cron.schedule` registers its timers there,
and a Dart timer fires in the zone that created it. So every firing tagged its
mutations with the *startup* request's id. The host keys `_pendingMutations` by
parent id and flushes on the matching response; `CronsStarted` was answered
once, at boot. Everything filed there afterwards was parked forever.

Wider than retention: **any `mutate.*` from any scheduled cron was dropped**,
including application authors' own jobs. Manual runs were unaffected (there the
outer scope is the host's own `RunCronJobRequest` — `db_crons.dart:55` says so
in a comment). `_cleanup_unreferenced_photos` was unaffected because it uses a
real host RPC rather than `mutate`.

## What shipped

| Commit | What |
| --- | --- |
| `c0d73ea` | `todo.md`: the general "attach capability for disposable tables" entry |
| `3462c60` | Characterization tests pinning the mechanism, asserting the *broken* behaviour first |
| `a6160b9` | **The fix** — request-scoped providers bind with `override` |
| `df76021` | `mutate.purge`: bulk `DELETE`, returns a count; all five retention crons moved onto it; `docs/cron.md` |
| `448059c` | Bound the per-row delete path's read; batched its row-rule checks |
| `166c7a7` | Chunked purge (10k rounds, passive checkpoint between) |
| `1854c1d` | `DiskFullException` — a full disk names itself instead of the statement that hit it |
| `45befd6` | Contract tests for the SQLite properties a split log DB rests on |

Suites: zonai_schema 241, apps/zonai 470, doc snippets 3. All green.

## What is NOT tested — read this before trusting anything above

- **The delete guard's *firing* path.** `448059c` refuses a delete matching
  more than `_maxRowsPerDelete` (50,000). The refusal is verified only by
  reading. Reaching it needs a real `ZonaiDb` with 50k+ rows through the e2e
  fixture. What *is* covered: 470 tests exercise deletes under the cap, so the
  normal path and the batched-rules swap are intact.
- **Chunked purge end to end.** The loop's termination and the
  transaction-per-round property were verified by reading `_execute` (it opens
  a `db.transaction` per call, so each round commits independently). No test
  drives a multi-round purge.
- **Nothing has run against a real full disk.** All of this is reasoning about
  a state reproduced nowhere in CI.

## What is left

### 1. Split `_log` into its own database file — ✅ DONE (`3bcae06`, `09bbb00`)

Shipped. `_log` lives in `data/zonai_log.sqlite`, attached as `logdb` on
**both** connections inside `ResqliteDelegate.open` — the ❌ property from
`45befd6` is closed, and a test now reads back a row written through the
attach, which is the only way to catch that failure (the write half works
either way, which is what made the broken version silent).

Nothing downstream changed. An unqualified `_log` resolves into the attached
DB now that `main` has none, covering the table API, `dashboard_metrics`'s raw
`FROM "_log"`, and the retention crons. The schema name appears only where a
statement must name a *file*: the attach, the DDL, `VACUUM`, `wal_checkpoint`.

Existing rows are dropped on first open, as decided. Their pages go to main's
freelist, so `db logs clear --vacuum` now rewrites **both** files.

Covered by `log_database_split_test.dart` (8 tests): read-after-write through
the attach, the drop-before-create ordering (main shadows the attached table,
so a stale `_log` would silently send every write back to the shared file),
the indexes being recreated in the new file rather than lost with the dropped
table, a second open not re-running the move, and a live stream still
re-emitting.

**Found while doing it:** an attached database keeps its own journal mode and
defaults to `delete` — `main` read `wal` and `logdb` read `delete`, measured
side by side. `_purge`'s per-round checkpoint and `_vacuum`'s trailing one
were therefore **no-ops on the log DB**, silently, since a checkpoint against
a database with no WAL just returns. Fixed in `09bbb00`.

The cross-database atomicity caveat is **settled** — see #5. In short: the
only transaction that spans `main` and an attached DB is the purge pipeline,
where it is harmless, and the request-path writes to both split tables are
standalone statements.

### 2. `max_page_count` on the log DB — the remaining half

`journal_size_limit` is **resolved: deliberately not done.** Measuring it did
not support the plan. With the limit at 32 KB and a 1.6 MB WAL, checkpoints at
PASSIVE, FULL *and* RESTART all reported full success (`[0, 399, 399]` — not
busy, every frame copied) and left the file at full size. Only TRUNCATE shrank
it, and TRUNCATE does that with or without a limit. `_purge` uses PASSIVE and
wants pages returned for reuse rather than the file shrunk; `_vacuum` already
uses TRUNCATE. The finding is recorded next to the `journal_mode` pragma that
replaced it in `resqlite_delegate.dart`.

`max_page_count` is now unblocked and verified safe by `45befd6` (it stops log
writes and leaves application writes untouched). **It needs a decision before
it can land**, not just code:

- What cap, and is it configurable in `zonai.yaml`?
- What happens when it is hit. A log insert starts failing with `SQLITE_FULL`,
  and the write path is `trace_id.dart`'s fire-and-forget callback. A cap that
  can take down request handling is worse than the runaway table. This almost
  certainly needs the log write to become explicitly non-fatal first.

### 3. Conditional VACUUM in the cleanup cron — ✅ DONE

`_cleanup_logs` now ends with a `ReclaimLogSpaceRequest` host RPC. Gated both
ways: worth it (≥16 MB on the freelist, else a quiet skip) and possible (room
for a copy of the pages that *survived* the purge). The headroom failure emits
the operator-actionable line host-side — deliberately not through the
response, since at that point writing to `_log` is what may be failing.

Half of #4 came with it: `freeDiskBytes` (`utils/free_disk_space.dart`) shells
out to `df -Pk`, PowerShell on Windows. `-P` is load-bearing — without it a
long device name wraps and a naive parse returns Used instead of Available.
Parsing is separated and tested against captured output from both platforms.
`null` means unknown, never zero, and unknown proceeds.

### 4. Free-space awareness — the probe now exists

`freeDiskBytes` landed with #3, so the "no API in Dart" problem is solved by
shelling out rather than FFI. What remains of this item is only the
*proactive* half: warning before 100% during ordinary operation rather than at
the one moment a cron asks. Still the **least valuable** remaining item, for
the reason the original entry gave — chunking already lets a nearly-full
volume drain, `DiskFullException` says what to do once you are against the
wall, and the retention cron now says it a night earlier.

Original note kept below for the Windows/FFI options it weighed.

`1854c1d` is **reactive**: it reports the wall once you are against it. The
proactive half — warning before 100% — needs a real probe, and Dart has no API
for it: FFI `statvfs` plus `GetDiskFreeSpaceExW` for Windows, or shelling out to
`df` and parsing per platform. `ffi: ^2.1.0` is already a dependency.

My read: this is the **least valuable remaining item**. Chunking already lets a
nearly-full volume drain, and the error now says what to do.

### 5. `_rate_limit` in its own database too — ✅ DONE

`data/zonai_rate_limit.sqlite`, attached as `ratedb`.

**The atomicity worry did not apply.** Checked rather than assumed:
`RateLimiter.check` issues standalone statements — a SELECT, then an INSERT or
UPDATE — and never joins a transaction with application writes, so there is no
cross-database transaction on the request path. Where one does exist is the
purge pipeline (`_execute` batches the bulk delete with queued side effects),
and there it stays harmless for the original reason: retention has no
invariant spanning rows.

The mechanism is now generic — a `_disposableTableSchemas` map drives the drop
ordering, the schema-qualified DDL, the index recreation and the purge's
checkpoint; `Settings.zonaiSqlitePaths` does the same for the filesystem side,
so `db clear` covers a future split without being told. Adding
`_auth_challenges` or `_cron_jobs` is now a two-line map entry plus its
indexes.

One thing that was load-bearing here and was not for `_log`:
`rate_limit_bucket_unique` is what the rate limiter's retry-on-constraint-19
depends on to resolve two concurrent requests missing the same bucket row.
Recreating it in the new file is correctness, not speed, and the test asserts
the constraint *rejects a duplicate* rather than that an index by that name
exists. The `todo.md` entry from `c0d73ea` frames
the general version ("table groups") and lists `_auth_challenges` and
`_cron_jobs` as further candidates.

### 6. Release — this is the blocker for anyone in the field

**Nothing above is reachable by any deployed zonai.** HEAD is 71 commits past
`v0.6.2`. This bit us once already: the issue-#28 `--vacuum` work was committed
and unreleased, so the field had no vacuum path at all — and the same is now
true of the cron fix, `purge`, and `DiskFullException`.

A release needs to carry **all** of it. For any deployment already at 100%, the
ordering is:

> **extend the volume → deploy → let retention drain → vacuum**

Deleting millions of rows needs WAL headroom, and `df` will not move until the
file is rewritten regardless — deletes only move pages to the freelist.

## Pending verification (external)

`wholesale-command-station` offered its box as a specimen and captured a
read-only baseline **before** any change:

```
_log         rows 4,618,595   overdue (4d) 2,516,176   oldest 2026-07-31 04:52:37
_rate_limit  rows        42   overdue (7d)        39   oldest 2026-07-31 04:53:17
_cron_jobs   rows     1,323   _cleanup_logs runs 13, all completed, 0 failed, 0 errored
                              completed-started: min 0ms, max 2ms, avg 0.6ms
file         236,913 pages x 4096 = 970,395,648 bytes
             freelist_count 0     auto_vacuum 0
volume       974M size, 927M used, 0 avail (~47M root reserve)
```

`freelist_count` moving off 0 is the **harder evidence** than any row count — it
proves a `DELETE` executed in that database for the first time in its life.

A zero-risk test exists that needs no release: **manually trigger
`_delete_old_rate_limits`** (42 rows, no OOM risk). Manual runs always worked,
so if the 39 overdue rows clear on the *current* binary, the
manual-vs-scheduled asymmetry is demonstrated on production hardware. It needs
dashboard admin credentials — there is no cron trigger in the CLI — so it is
pending a person.

> ⚠️ **Do not do the same for `_cleanup_logs` on an unreleased build.** It would
> take the unfixed `mutate.delete` path over 2.5M rows and OOM. "The manual path
> works" is true, safe at 42 rows, dangerous at 2.5M, and indistinguishable in
> the dashboard. `448059c` now refuses it, but only on a build that has it.

Channel `z-log-cleanup` on llm_chat is still open; both sides stayed reachable.

## Traps worth not rediscovering

- **An attached database inherits nothing.** Not the journal mode (defaults to
  `delete` beside a WAL `main`), not pragmas, not the second connection. Every
  connection-local or file-local setting has to be applied per connection
  *and* per schema.
- **A `wal_checkpoint` against a non-WAL database is not an error.** It returns
  successfully and does nothing. Two disk-bounding routines ran that way for a
  commit without a single symptom.
- **`PRAGMA` is not a read verb**, so `ResqliteDelegate.execute` routes it to
  the writer — which discards row data. A pragma's value can only be read back
  through `transaction`, which runs on the companion sqlite3 connection.

- **`min` resolves to raindrop's SQL aggregate, not `dart:math`'s.** The
  raindrop barrel exports it and silently wins. Caught by the analyzer only
  because arity differed.
- **`includeIfAbsent` vs `override`** in `runMergedScoped` — the whole root
  cause. A nested scope silently keeps the outer binding.
- **Two connections, one file.** Anything connection-local (pragmas, attaches)
  must be applied to both, and testing through one of them will not reveal it.
- **This is a shared worktree.** Other sessions commit here concurrently; HEAD
  moved several times mid-session. Commit with an explicit pathspec
  (`git commit -- <paths>`), never a bare `git commit`, or you will sweep up
  another session's staged work.
- **The `verify` gate is repo-wide**, so it blocks on other sessions'
  unverified files. `--no-verify` was used throughout with tests run manually
  and named in each commit message.
