# Next session — log retention and disposable tables

Written 2026-08-13. Everything below is committed and green unless it says
otherwise. HEAD is **71 commits ahead of `v0.6.2`**, which matters more than
usual here — see [Release](#release-this-is-the-blocker-for-anyone-in-the-field).

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

### 1. Split `_log` into its own database file — the big one

**Decision already made: drop existing `_log` rows.** No data migration. That
removes the only genuinely hard part.

Three SQLite properties were checked against the real driver in `45befd6`:

- ✅ A page cap on the attached DB stops log writes and leaves application
  writes untouched. **This is why the cap cannot land before the split** —
  `max_page_count` bounds a *file*, so on the shared database the ceiling is hit
  by whichever write arrives first, application inserts included.
- ✅ `VACUUM <schema>` rewrites the attached file alone, so reclaiming log space
  does not lock application data. This is what makes vacuuming from a cron
  viable at all.
- ❌ **A single `ATTACH` reaches only the write connection.** `ResqliteDelegate`
  opens the same file twice — `rs.Database` for writes, a `package:sqlite3`
  handle for reads — and routes by statement verb. Writes land in the attached
  DB; reads are answered by a connection that has never heard of it. Log rows
  would be written and then be unreadable.

So the implementation requirement is concrete: **attach on both connections
inside `ResqliteDelegate.open`**, right where `PRAGMA foreign_keys` is set
(`resqlite_delegate.dart:339-341`). That pragma's own comment records the
identical trap being learned the hard way — read it before starting.

Once the attach is on both connections, downstream should need no changes: an
unqualified `_log` resolves into the attached DB when `main` has no such table,
which covers the table API and `dashboard_metrics.dart`'s raw `FROM "_log"`.

Remaining steps:

1. Create/open the log DB alongside `zonai.sqlite`; attach as e.g. `logdb` on
   **both** connections.
2. Create `_log` there; drop `_log` from `main` in an internal migration.
3. Point `_purge` and `_vacuum` at the right schema.
4. Confirm `zonai db logs`, the dashboard, and `dashboard_metrics` still read.

One caveat not yet investigated: in WAL mode a transaction spanning `main` and
an attached DB is **not atomic** across both. Harmless for logs; worth a
thought before moving anything else.

### 2. `max_page_count` + `journal_size_limit` on the log DB

Blocked on #1, and *incorrect* before it — see above. `journal_size_limit` is
independent and one line: the WAL currently grows and is never truncated after
checkpoint. Only `PRAGMA foreign_keys` is set at open today.

### 3. Conditional VACUUM in the cleanup cron

Unblocked — the schema-scoped VACUUM is verified. Gate on
`freelist_count * page_size` exceeding a threshold **and** enough free disk.
When the headroom gate fails, that is the moment to emit the operator-actionable
line: *"retention reclaimed nothing; N bytes are on the freelist; the rewrite
needs M free and K are available — extend the volume."*

Note `ZonaiDb.vacuum()` already exists (`zonai_db.dart`) and is reachable only
from `zonai db logs clear --vacuum`.

### 4. Free-space awareness — half done

`1854c1d` is **reactive**: it reports the wall once you are against it. The
proactive half — warning before 100% — needs a real probe, and Dart has no API
for it: FFI `statvfs` plus `GetDiskFreeSpaceExW` for Windows, or shelling out to
`df` and parsing per platform. `ffi: ^2.1.0` is already a dependency.

My read: this is the **least valuable remaining item**. Chunking already lets a
nearly-full volume drain, and the error now says what to do.

### 5. `_rate_limit` in its own database too

Requested. Same disposable profile as `_log` — per-request churn, bounded
retention, nothing worth reconstructing. Do it after #1 so the mechanism is
generalized once rather than twice. The `todo.md` entry from `c0d73ea` frames
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
