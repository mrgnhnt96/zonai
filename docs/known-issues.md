# Known issues

Bugs found incidentally while integrating an external client app against
zonai on 2026-07-24/25. Neither is caused by or related to that work — both
are pre-existing and reproduce identically on a clean checkout with no
schema/endpoint changes at all. Filed here so a fix can be picked up
independently.

**Update 2026-07-25: both fixed.** `BlackList implements LifecycleComponent`
now — confirmed by regenerating `.revali/` and finding `BlackListGuard(di)`
wired into `auth`/`db`/`img`/`email`'s generated routes. `schema_table_discovery.dart`'s
`AnalysisContextCollection` resolution issue is fixed too — confirmed by
re-running `dart run tool/generate_internal_db_artifacts.dart --migrate
--name <table>` from `apps/zonai` against a scratch table added under
`libs/zonai_schema`, which succeeded and produced a real migration file.
Re-ran `dart analyze`/`dart test` across `libs/zonai_schema`, `apps/zonai`,
`apps/server` — same results as before; nothing regressed. Left below for
reference/history.

**Update 2026-07-26: fixed.** Root cause was on the **host** side, not the
worker side the "suggested fix" below points at — `MessageHandler`'s
`_pendingHostReplies` (worker-side) was already correctly keyed by request
id and never confused two in-flight requests. The actual bug was
`Mailman._send`/`_sendOnce` in `apps/zonai/lib/src/db_mutator/mailman.dart`:
it fully serialized each outgoing request through `_sendChain`, including
the *wait for the worker's reply*, not just the stdin write. `_list`'s
per-row `_requireRowAccess`/`_requireTableAccess` always calls back into
the same `RulesMailman` to check row/table rules (`__utils.dart`) — so when
a row rule's own `get.one`/`get.many` needs the host to answer a nested
`GetRecordRequest`, satisfying that read calls `zonaiDB.list`, which calls
`RulesMailman.send(...)` again for the *nested* table's row rules. That
nested send queues behind `_sendChain`, which is still occupied waiting on
the *outer*, still-unanswered request — a real circular wait, not just a
slow path. It only ever resolved because `_sendOnce`'s hardcoded 1-second
`.timeout()` forced the outer request's entry out of `_pendingResponses`,
unblocking the chain — at which point the outer request's real (late)
reply arrived with nowhere to land, logged as `Received response for
unknown request` (or `Received error for unknown request`, if the nested
call itself failed first). **Fixed** by splitting `_send` into a
`_writeOnce` step (still serialized via `_sendChain` — restart-check,
process start, the actual stdin write) and a separate, unserialized
`_awaitOnce` step (the timeout-guarded wait for the reply), so a reentrant
send to the same worker no longer queues behind its own outer request.
**How this was confirmed**: added a scratch row rule
(`PostRowRules.canView` in `apps/playground`) that calls
`get.one(tableName: 'companies', ...)`, compiled and ran the real
playground server end to end (not a unit test — this app has no existing
Mailman test coverage), and hit `GET /db/list?table=posts` for real.
Before the fix: reproduced the exact symptom in the report below,
including a real `TimeoutException after 0:00:01.000000` at
`Mailman._sendOnce` and a live `[RULES_EXE]: Received error for unknown
request` log line. After the fix: the same call resolves in well under a
second with no timeout and no unknown-request log line, end to end. Left
below for reference/history.

**Update 2026-07-26: reclassified — likely not a zonai bug.** Could not
reproduce the crash as a genuine application defect despite substantial
live testing: ran the real compiled binary (`dart compile exe
-D__ZONAI_COMPILED__=true`, matching how `zonai build` actually produces
`kIsCompiled=true`) against `apps/playground`, both idle and under
continuous `/health` polling and real `/db` create/list traffic, for
several minutes at a stretch with no crash — well past the "~5-10s" /
"~30s" windows claimed below. It *did* die once, but the captured death
sequence didn't match this entry's own symptom at all: no 20-second
health-check-exhausted retry, no `Unexpectedly failed to make connection`
log line — it jumped straight from normal request handling into
`Kill.force()`'s own sequence (`'Killing process'` →
`cleanUp.run()` → worker kills → `exit(0)`), which only runs when `Kill`'s
`SIGTERM`/`SIGINT` watcher fires (`apps/zonai/lib/src/domain/kill.dart`).
That points at an external signal, not a Revali re-entry bug. Checking
`override_canvas` (the project this was originally found in) turned up
direct corroboration in its own `todo.md`, written the same session,
in an aside about testing CORS: *"background zonai server processes kept
dying between separate shell tool invocations for reasons not fully
root-caused — `disown`ing the process helped but didn't fully eliminate
it; a real terminal session would not have this problem."* Same symptom
class (a backgrounded `zonai serve` dying with no application-level
cause), same night, independently noticed. The likely real mechanism:
running `zonai serve` as a backgrounded job across many separate
shell-tool invocations (an agentic dev-tool pattern, not a real terminal
session) without detaching it (`disown`/`nohup`/`setsid`) leaves it
attached to a shell process that the tool harness can cycle or reap
between calls, which can deliver `SIGHUP`/`SIGTERM` to the whole process
group. This entry's own "ruled out" section only tested a trivial
`sleep`-loop background job surviving in the same environment — that
doesn't rule out job-control differences for a real process tree with
open sockets and child workers, which is a meaningfully different shape.
**Not changing** the "explicitly ruled out" / "suggested next step"
write-up below — left as-is for whoever wants to dig further or has a
setup where this still reproduces; if it does, get a *live* debugger
attached to a `dart run` (non-compiled) process from a real terminal
session, since that's the one repro condition that hasn't actually been
tried yet.

## 17. `resqlite` segfaults reading diagnostics when a connection handle was never opened — fixed

**Fixed 2026-08-19** in the submodule, not here: `libs/resqlite` is a separate repository
(fork `mrgnhnt96/resqlite`, branch `zonai`, commit `1d6e270`). Suite went 163 passed/4 skipped
to 169 passed/3 skipped; the two remaining resqlite skips are #16.

It reproduced in about a second, and after the fix the same command passes:

```sh
cd libs/resqlite
dart test test/stream_test.dart -j1 --run-skipped \
  -n "stream entry is removed from registry after last listener cancels"
# was: exits 134
```

**The crash was not where the quarantine notes said.** They described "a near-null dereference
in the native stream-registry teardown path". The stack never mentioned stream teardown:

```
sqlite3_db_status64+0x34        <- si_addr=0x18
sqlite3_db_status+0x28
resqlite_db_status_total+0x11c
Database.diagnostics.readCounter
Database.diagnostics
_streamLength                    <- the test helper
```

It was the diagnostics counter read. That also explained the population: all five quarantined
tests in that file assert on the registry *via* `diagnostics().streamLength`, and it was the
shared `diagnostics()` call that crashed, not the shared subject matter.

**Root cause — TWO unguarded sites, not one.** `resqlite_db_status_total` walks the writer and
then every reader slot, handing each connection to `sqlite3_db_status`. Both kinds of handle are
opened lazily, and nothing on this path opens one:

- `db->writer` is `NULL` from `:637` until `ensure_writer_open` runs. Never called here.
- `db->readers[i].db` is `NULL` from `:650` until `ensure_reader_open` runs. Never called here.
  `:648` sets `reader_count = max_readers` — slots, not open connections — so a slot that never
  served a query is still NULL.

The fix skips an unopened handle at both sites. That is the correct total and not merely a crash
guard: a connection that was never opened has allocated nothing for these counters to report, so
it contributes 0.

**The "only one unguarded site" claim in the first diagnosis was wrong, and the way it was wrong
is the reusable lesson.** It rested on `grep -n 'readers\[i\]\.db'` returning exactly three hits.
That grep could not have found the writer no matter what the code did — the search term already
assumed the answer was a reader. Fixing only the reader loop moved the crash from
`resqlite_db_status_total+0x11c` to `+0x84`, same `si_addr=0x18`, and left the whole
`diagnostics_test.dart` suite still aborting. **A grep shaped like the hypothesis cannot falsify
the hypothesis**; the thing that caught it was running the full suite and noticing a second
quarantine with an identical signature.

**Why a SEGV rather than `SQLITE_MISUSE`, and why `0x18` is exact.** `sqlite3_db_status`
NULL-checks only under `SQLITE_ENABLE_API_ARMOR`, which is not among the defines in
`tool/build_native.dart:220-236` (confirmed against the actual `clang` invocation, not just the
build script), so the first statement is `sqlite3_mutex_enter(db->mutex)`. In `struct sqlite3`,
`mutex` sits at offset 24 — `0x18`, byte-for-byte the reported `si_addr`. **Still worth pricing
separately:** adding `SQLITE_ENABLE_API_ARMOR` to the build turns this entire class of mistake
into `SQLITE_MISUSE` instead of a process abort, and would have made both sites a returned error
code rather than a hunt.

**Why it mattered beyond five tests**: it aborted the process, so `dart test` exited 134 with no
summary and one segfault took down visibility into every other resqlite test. A whole
`diagnostics_test.dart` suite was quarantined for it too — that one was missed by the first
diagnosis, which counted only the five in `stream_test.dart`.

**What it did *not* affect**: zonai never calls `Database.diagnostics()` — zero callers outside
resqlite's own tests — so no zonai runtime path could reach this. The value recovered is the six
tests, five of which are stream-registry leak guards for the API `resqlite_delegate.dart:477`
depends on.

## 16. `resqlite` readers cannot open a database until something has written to it — diagnosed, not fixed

Two tests are quarantined with `ResqliteQueryException: reader not open`
(`database_test`'s "select rejects too few parameters on cached statements" and
`reader_error_reporting_test`'s "reader prepare failure uses reader sqlite error message").
Both reproduce on macOS locally and on Linux CI.

**Root cause.** `open_connection` gives reader connections `SQLITE_OPEN_READWRITE` **without**
`SQLITE_OPEN_CREATE`, while SQLite defers creating the database file until a first write.
Verified with the `sqlite3` CLI:

| writer did                          | file on disk |
|-------------------------------------|--------------|
| open with CREATE, then nothing      | **does not exist** |
| open with CREATE, then CREATE TABLE | exists, 8192 bytes |

So between `Database.open(path)` and the first write there is no file, and the reader's
`sqlite3_open_v2` without CREATE returns `SQLITE_CANTOPEN` — code 14, exactly what both failures
report — which surfaces as "reader not open".

**The control pair already exists in the repo**, same file and same setup, differing in one thing:

| test                          | writes first?                  | result |
|-------------------------------|--------------------------------|--------|
| `reader prepare failure ...`  | no — opens, selects immediately | fails "reader not open" |
| `reader bind failure ...`     | yes — `CREATE TABLE` then selects | passes |

Note the failing exception carries `Params: [first]`: it is the test's *first* select that
throws, the one expected to succeed, so the assertion the test is actually about is never reached.
The tests are not wrong.

**Relationship to #17 — established, not assumed.** They share a precondition, not a defect. A
failed `ensure_reader_open` leaves `readers[i].db == NULL`, which is one producer of the NULL
that #17 dereferenced; but #17 did not need this bug, because a slot that was simply never used
is NULL by design. Neither fix resolves the other, and #17 being fixed (2026-08-19) leaves this
one exactly where it was — the guard makes an unopened handle *harmless*, it does not make a
reader *able to open*.

**Fix — decided 2026-08-19: treat CANTOPEN-on-missing-file as "no rows yet".** The three options
were: give readers `CREATE` (but then a reader can create a stray file, which is what the missing
flag was buying), have the writer materialize the file on open (but then opening a database
always touches disk), or report an empty result for a database that does not exist yet. The last
was chosen because it is the only one that preserves the no-stray-files property the missing flag
was there to buy.

## 15. An update that writes the column its own `where` matched on reported failure for a write that succeeded — fixed, and `PATCH /db` now 404s on no match

**Fixed 2026-08-13** (`a16b499`). Reported from the field as *"`PATCH /db` 500s
on any `where` that isn't on `id`; a plain `eq` on `place_id` is enough, while
`list` accepts the same clause happily."* **That rule is wrong** — a non-id
`where` works, and the read/write asymmetry does not exist: `list` and `update`
build their clause through the same `_whereFilter`
(`table_operations.dart:188` and `:441/458/493`), `Eq` renders
`"t"."place_id" = ?` exactly as it renders `"t"."id" = ?`
(`where_sql.dart:38`), SQLite accepts either in an UPDATE's WHERE, and 52
existing tests already compile *and execute* `update(..., where: Eq('title',
…))`. But the report was pointing at two real defects, and `id`-matched updates
are immune to both, which is what made the pattern look like it did.

**1. The read-back replayed the pre-update `where`.** `updateResult.rows` is
always empty, so `_update` refetched — by re-running the read it had built
*before* the write. An update that writes a column its `where` matched on moves
the row out of its own clause: `WHERE status = 'open'` while setting `status =
'closed'` matches nothing on the second pass. The write was already committed,
so **the caller got a failure for an update that succeeded**, and a retry then
matched nothing at all. `AfterUpdateExtensionRequest` also received a
`before`/`after` pair of different lengths — its assert names this exactly.

That assert is why the failure had two faces and never looked like one bug:
under `dart test` (asserts on) it throws there; in a **compiled binary asserts
are off**, so the empty result travelled on to `DbHandler.update` and 500'd
there instead. Now keyed by the ids read before the write, so the read-back
finds its rows whatever the update did to them. The same defect was on the
`mutate.update` side-effect path — the one scheduled crons take — and was fixed
with it.

**2. Zero rows matched was a 500.** That is an ordinary outcome of a
conditional update ("close it if it is still open"), and `StateError` left a
caller unable to tell *the row is gone* from *zonai broke*.

> ⚠️ **Behaviour change.** `PATCH /db` and `PATCH /db/custom/:operation` now
> return **404** when no row matches, not 500. Any client treating 500 as
> "not found" needs updating. `PATCH /db/many` is unaffected — it returns an
> empty list, as it always did.

**Coverage**: `apps/zonai/test/e2e/update_where_column_e2e_test.dart`, four
cases against a real fixture project and a real database, asserted red first.
The where-rewrite case reproduced the length assert *and* confirmed the write
had landed anyway; the non-id-untouched and by-id cases passed before and
after, which is what disproves the reported rule.

**Not covered**: an update that rewrites the `id` column itself moves its rows
out of the new clause too. Nothing does that, and a table whose ids are
reassigned by an update has no stable way to be read back at all.

## 14. `ZONAI_FORCE_WORKERS=1` never starts under `dart run` — the health check gives up 20s before `revali dev` is ready — not fixed

**Severity: the documented escape hatch is unusable in dev.** Compiled binaries
are unaffected, so nothing shipped is broken — but `ZONAI_FORCE_WORKERS=1` is
referenced in ~14 doc pages as the way to exercise the worker path, and it
cannot currently be exercised that way at all. Found 2026-08-12 while trying to
reproduce #27 over the wire.

**Reproduction**, from `apps/playground` on a clean, freshly-compiled project:

```
# works
dart run ../zonai/bin/zonai.dart serve --no-version-check
# → [CONFIG_EXE]: Started / Serving at http://:::8080/

# hangs, then dies
ZONAI_FORCE_WORKERS=1 dart run ../zonai/bin/zonai.dart serve --no-version-check
# → Checking health of Revali (server) - Attempt 0
#   ... Attempt 199
#   Unexpectedly failed to make connection to Revali (server)
```

No `[CONFIG_EXE]` line ever appears in the failing run — the config worker is
never spawned, so the server has nothing to become healthy *with*. Confirmed
with fresh workers and a clear port; it is not the stale-executable problem in
issue 15 below, and not a port conflict.

**Root cause.** Three decisions compose into this, each defensible alone:

1. `resolveProjectLink` (`project_link.dart:83`) returns
   `ProjectLink.skip('$kForceWorkersEnv is set')` — so no project entry is
   generated or run.
2. `maybeReexecProjectRuntime` (`project_runtime.dart:59`) returns early on
   `forceWorkers`, so the CLI stays on the bootstrap binary and
   `HostWorkerRegistries.operations` is never assigned.
3. `Revali._inProcessHttp` (`revali.dart:22`) is
   `kIsCompiled || HostWorkerRegistries.hasOperations`. Under `dart run`,
   `kIsCompiled` is false and `hasOperations` is now false too — so `start()`
   takes `_startDebug`, which shells out to `dart run revali dev` in
   `apps/server` and polls for health 200 times at 100ms.

20 seconds is not close to enough for `revali dev` to generate and compile, so
it always times out.

The env var is meant to change **dispatch** (ops/rules over IPC instead of
in-process). It also changes **how the server is hosted**, which nothing
intends. Note the generated entry already guards its own registry assignment on
`forceWorkers` (`project_generator.dart:34`), i.e. it is written to *run* under
force-workers and simply not populate the registries — but (1) means it is
never run at all. Those two are in direct disagreement, and that is the bug.

**Suggested fix**: stop letting `forceWorkers` suppress the project link.
Generate and run the entry as normal and let its existing
`if (!HostWorkerRegistries.forceWorkers)` guard do the work it was written for
— registries stay empty, dispatch goes over IPC, and `_inProcessHttp` keeps
serving in-process because the entry ran. That makes the env var mean only what
it says.

If that turns out to be load-bearing elsewhere, the fallback is to decouple
`_inProcessHttp` from `hasOperations` — but the disagreement above should be
resolved either way, or the next person hits the same thing.

**How to verify a fix**: the reproduction above should serve under
`ZONAI_FORCE_WORKERS=1`, log `[RATE_LIMITS_EXE]: Started`, and answer a request
end to end. Assert on the worker actually being spawned (the `[*_EXE]` lines),
not just on the server binding a port — binding is what already works.

## 13. `alterColumn`'s generated rebuild migration uses a positional `INSERT INTO ... SELECT *`, silently shuffling data into the wrong columns once a table has ever grown a column via `ALTER TABLE ADD COLUMN` — fixed

**Update 2026-07-30: fixed.** `mrgnhnt96/raindrop` (`zonai` branch,
`d3b001f`): `_rebuildTableFromAlters` (`sqlite_ddl.dart`) now builds the
`INSERT`/`SELECT` from `tableColumns` explicitly — the exact fix suggested
below — instead of a positional `SELECT *`, so a rebuilt table's rows land
by column *name* regardless of how the source table's physical on-disk
column order has drifted from its declared order. Added a regression test
in `packages/raindrop_sqlite/test/sqlite_ddl_test.dart` (`inserts by
explicit column name, not positional SELECT *`) using a `tableColumns`
list whose order differs from a plausible physical layout, asserting the
generated SQL is `INSERT INTO ... (col, col) SELECT col, col FROM ...`
and never contains `SELECT * FROM`. Existing `alterColumn`/`generate`
tests in the same file still pass unchanged. This repo's `libs/raindrop`
submodule pin bumped to `d3b001f` to pick up the fix. Left below for
reference/history.

**Severity: silent data corruption on `db migrate apply`, not just a crash** — the crash (a `NOT NULL` constraint failure) is the *lucky* outcome; if every column in the rebuilt table happened to be nullable, this would corrupt real data with no error at all. Found 2026-07-30 in `override_canvas`, applying two long-pending migrations (`make_recording_client_app_and_org_nullable`/`make_recording_owner_id_nullable`, generated in an earlier session but never actually run against the real dev database until this one).

**Reproduction**: any table that (a) has ever had a column added via a bare `ALTER TABLE ADD COLUMN` (which appends physically, at the end of on-disk column order) and (b) later goes through `alterColumn`'s rebuild path (e.g. widening a column to nullable) will have its rebuilt copy's rows shifted. Concretely, `recordings` had `sequence`/`session_id`/`organization_id` added later via separate `ALTER TABLE ADD COLUMN` calls, so its physical column order (`api_key, app_version, client_app_id, created_at, data, duration_ms, format_version, id, metadata, owner_id, platform, size_bytes, sequence, session_id, organization_id`) no longer matched the rebuilt table's declared/alphabetical order (`..., organization_id, owner_id, platform, sequence, session_id, size_bytes`). Applying the migration failed with:

```
SqliteException(1299): while selecting from statement, NOT NULL constraint failed: recordings_raindrop_rebuild.size_bytes, constraint failed (code 1299)
  Causing statement: INSERT INTO "recordings_raindrop_rebuild" SELECT * FROM "recordings"
```

— because position 15 in the *old* table (`organization_id`, nullable) was being inserted into position 15 of the *new* table (`size_bytes`, `NOT NULL`).

**Root cause.** `libs/raindrop/packages/raindrop_sqlite/lib/src/sqlite_ddl.dart:153`, inside `_rebuildTableFromAlters`:

```dart no-analyze
'INSERT INTO $temp SELECT * FROM $table;',
```

`$temp`'s `CREATE TABLE` (line 132: `tableColumns.map(_columnDefinition).join(...)`) is built from `tableColumns` — the schema's own declared/sorted column order — but `$table`'s actual on-disk physical column order can diverge from that the moment any column was ever added via `alterColumn`'s sibling `addColumn` path (a plain `ALTER TABLE ADD COLUMN`, which SQLite always appends physically regardless of where the column sits in the schema's declared order). `SELECT *`/bare `INSERT INTO` both resolve by *position*, not name, so once the two orders diverge, every column from the divergence point on gets inserted into the wrong slot.

**Worked around, not fixed here** (in `override_canvas`, not this repo): hand-edited the two pending migration files to use explicit, name-matched column lists on both sides of the `INSERT`/`SELECT` instead of relying on position — safe to do only because neither migration had ever actually been applied anywhere yet (confirmed via the `_raindrop_migrations` tracking table). This is a per-migration-file workaround; every future `alterColumn` rebuild on a table with this history will hit the same bug again until it's fixed at the source below.

**Suggested fix**, in `_rebuildTableFromAlters` (`sqlite_ddl.dart`): build the `INSERT`/`SELECT` from `tableColumns` explicitly, the same list already used to build `defs`, instead of `SELECT *`:

```dart no-analyze
final columnNames = tableColumns.map((c) => escapeName(c.name)).join(', ');
steps.addAll([
  'CREATE TABLE $temp (\n  $defs\n);',
  'INSERT INTO $temp ($columnNames) SELECT $columnNames FROM $table;',
  'DROP TABLE $table;',
  'ALTER TABLE $temp RENAME TO $table;',
]);
```

This is name-based and immune to physical/declared order divergence regardless of how the table got to its current on-disk shape.

**How to verify a fix**: reproduce by creating a table, adding a column via a plain `ALTER TABLE ADD COLUMN` (not part of the same migration as the original schema), then triggering an unrelated `alterColumn` rebuild (e.g. widening some other, earlier-declared column to nullable) on the same table — confirm the rebuilt table's rows land in the *same* columns they started in (assert actual values, not just row count) both before and after the fix; before the fix, at least one column's values should visibly land in the wrong column once the physical and declared orders diverge enough.

## 12. Compiled `zonai serve` segfaults seconds after startup on Linux x64/arm64 — `sqlite3LeaveMutexAndCloseZombie` — fixed

**Update 2026-07-30: fixed.** Found deploying `wholesale-command-station`'s
`apps/server`-shaped consumer app to Fly.io. Reproduced identically on real
Fly.io x86_64 hardware, emulated amd64, and native arm64, on both a
self-compiled binary and the official v0.3.4 release, always at the same
native frame:

```
===== CRASH =====
si_signo=Segmentation fault(11), si_code=SEGV_MAPERR(1)
  pc ... sqlite3LeaveMutexAndCloseZombie+0x170
```

100%-reproducible, not a race — crashed on the very first database open
every single time, including a lone `zonai db migrate apply` with no
worker subprocesses involved yet.

**Root cause**, isolated with a minimal standalone repro independent of
any zonai CLI machinery: `raindrop_sqlite`'s `ResqliteDelegate.open` opens
the same database file through *two separately-built SQLite libraries* —
resqlite's custom `sqlite3mc` build and `package:sqlite3`'s own,
separately dlopen-ed copy (the system `libsqlite3.so` on Linux). On
Linux, resqlite's `install()` loads with `RTLD_GLOBAL` (needed so
`@Native` process-lookup bindings can see symbols loaded via
`DynamicLibrary.open`), which exposes its sqlite3 symbols process-wide —
so `package:sqlite3`'s calls could cross into resqlite's
ABI-incompatible implementation (different `SQLITE_*` build flags affect
struct layout), corrupting connection state built by one implementation
when touched by the other's code. A repro combining just `resqlite` +
`package:sqlite3` against one file segfaulted inside the *system*
`libsqlite3.so` on the first query, every run.

**Never caught by existing tests** because they run on macOS, where
`DynamicLibrary.open` doesn't force global symbol visibility by default —
this is a Linux-only bug, which happens to be exactly the platform a
compiled server actually deploys to.

**Fixed**:
- `mrgnhnt96/resqlite` (`zonai` branch, `fd4ce41`): exports
  `installedNativeLibrary` publicly and adds every standard `sqlite3_*`
  symbol `package:sqlite3`'s FFI bindings require to the linker version
  script, so a consumer can point `package:sqlite3` at resqlite's own
  already-loaded library instead of a second one. All of these functions
  already existed in `sqlite3mc_amalgamation.c` — this only changes
  symbol visibility.
- `mrgnhnt96/raindrop` (`zonai` branch, `dd499e1`): `ResqliteDelegate.open`
  now does exactly that via `package:sqlite3`'s `open.overrideForAll`
  before opening either connection. Also constrains `sqlite3` to
  `<3.0.0` — 3.0.0 replaced the entire `DynamicLibrary`-based loading
  mechanism with Dart's build-hooks feature and dropped `open.dart`
  outright, which the fix depends on.
- This repo (`main`, `3404812`): bumps both submodule pins, and fixes a
  separate, real bug found investigating this — the spawner handles a
  `NativeLibraryRequest` from each of the 5 worker types independently,
  and `provideResqliteNativeLibraryPath`/`provideArgon2NativeLibraryPath`
  re-extracted the embedded native library from scratch on every call
  with no caching, so concurrent requests at startup could race to
  truncate/rewrite the same shared `.so` file. Now memoized per process
  (clearing the cache on failure so a transient error doesn't wedge
  future attempts), and the actual write is now atomic (temp file +
  rename in the same directory) as defense in depth.

**How this was verified**: a standalone repro exercising
`ResqliteDelegate.open` directly crashed on iteration 1 of 30 before the
fix, and passed 30/30 after it. End to end: a full `zonai build --release`
+ `zonai serve --release` cycle against `wholesale-command-station`'s real
schema, run 15 times from a completely fresh database each time (migrate
+ admin + serve + health check), was 15/15 clean after the fix (0/15
before it, on the exact same build pipeline). Deployed live to Fly.io —
stable, health check passing, no crashes.

## 11. `Jwt.parse` throws on a malformed token instead of returning `null` — fixed

**Severity: correctness/robustness.** `Jwt.parse`'s return type is `Jwt?`
and it already returns `null` for the wrong-number-of-parts case, but any
other malformation — corrupt base64url, a payload segment that decodes to
non-JSON or non-object JSON, or valid JSON missing fields `Jwt.fromJson`
needs — threw an uncaught exception instead. Found 2026-07-26 while
looking at `Jwt.parse` after fixing the adjacent base64url-padding bug in
the same method (see the padding fix already in this file's history for
that one — RFC 7515's stripped-padding convention vs. `base64Url.decode`
requiring a multiple-of-four length). Both `zonai_client`'s `Auth.jwt`
(called on every page load to read the stored token's claims) and the
server's `AuthHeaderRateLimit` guard call `Jwt.parse` directly with no
try/catch of their own, so a corrupted/stale/tampered token would crash
the caller instead of being treated as "not a valid token."

**How this was confirmed**: `Jwt.parse('header.${base64Url.encode(utf8.encode('not-json'))}.sig')`
threw `FormatException: Unexpected character (at character 1)` straight
out of `jsonDecode`, uncaught.

**Fixed**: wrapped the decode/`Jwt.fromJson` steps in a `try`/`on Object`
that returns `null`, matching the existing `Jwt.maybeFromJson` pattern
(and `parse`'s own already-established "return null" contract for the
wrong-part-count case). Regression coverage in the new
`libs/zonai_schema/test/src/types/jwt_test.dart`: wrong-part-count,
non-JSON payload, non-object JSON payload, JSON missing required fields,
and invalid base64url characters all now return `null` instead of
throwing; a real (unpadded) token still decodes correctly. `dart
test`/`dart analyze` clean across `libs/zonai_schema`, `apps/zonai`,
`libs/zonai_client`.

## 10. `POST /auth/reset-password` skips the send when email isn't configured and logs nothing — the docs promise a warning — fixed

**Note on the original diagnosis (2026-08-12).** This entry used to read
"crashes with an uncaught scoping error." **That crash no longer happens**,
and had not since 2026-07-31: `9054cf0` ("fix: log denial of unregistered
custom operation names") changed `zonai_schema`'s worker-side `logger` from
`read(_loggerProvider)` to `read(_loggerProvider, orElse: _Logger._)` — a
no-op fallback — as a side effect of unrelated work, and nothing recorded
that it had closed this crash. The reproduction and the severity argument
below still describe how this is reached and why it matters; the `Bad state:
read(ScopedRef<_Logger>)` output does not. What survived the accidental fix
was the other half of the same defect, and the half that was always the
point: the warning `docs/email.md` promises still went nowhere.

**Severity: breaks password reset outright for any app without SMTP configured**, which is presumably the common case for local dev and any fresh deployment before email is wired up — `docs/email.md` explicitly documents "If `AppConfig.email` is missing, send attempts are skipped and a warning is logged," which is not what actually happens. Found 2026-07-26 while adding a "forgot password" flow to `override_canvas`'s `apps/website`.

Between `9054cf0` and the fix below, the failure was silence rather than a
crash, which is harder to diagnose, not easier: every caller of
`courier.send` is fire-and-forget (`reset_password.dart:72`,
`magic_link.dart:92`, `verify_email.dart:80`, `otp.dart:69`), so an operator
running without SMTP saw a password-reset request return normally, no email
arrive, and nothing anywhere connecting the two.

**Reproduction** (against a real compiled `apps/server` binary with no `AppConfig.email` set, which is this app's actual current config):

```
curl -X POST /auth/reset-password -d '{"type":"sendResetPassword","table":"users","email":"real@example.com"}'

# as originally found (before 9054cf0): empty response, connection dropped, and
# in the server log:
Bad state: read(ScopedRef<_Logger>) was called in a scope which does not contain a corresponding value for the provided ref.
Did you forget to call: runScoped(() {...}, values: {value})?
Unhandled error while serving (process continues)

# between 9054cf0 and this fix: normal success response, no email, and nothing
# at all in the server log.
```

A second identical request within 60 seconds gets a normal `{"error":"Must wait 60 seconds before sending a new code"}` — confirming the *first* request's core logic (creating the `authChallenges` row, rate-limit bookkeeping) succeeds; the crash happens strictly *after* that, in the code path that's supposed to just warn-and-skip the actual email send.

**Root cause**, `apps/zonai/lib/src/email/courier.dart`'s `_Send._send`:

```dart no-analyze
Future<void> _send(Email email) async {
  final config = await configResolver.resolve();
  final emailConfig = config.email;
  if (emailConfig == null) {
    logger.warn('Cannot send email because email configuration is missing');  // <-- throws
    return;
  }
  ...
```

The original entry read this as a missing `runScoped` around the request path
and did not isolate further. That was the wrong `logger`. `courier.dart`
imported no logger at all — it imported `package:zonai_schema/zonai_schema.dart`,
whose barrel re-exports `src/handlers/messages/message_handler.dart` under a
`hide` clause covering `Request`, `Response`, `msg` and the native-library
types but **not** `logger`. So this line resolved to `zonai_schema`'s
worker-side `_Logger` (`libs/zonai_schema/lib/src/handlers/messages/deps/__log.dart`),
which `MessageHandler.listen` scopes inside a worker process and nothing
scopes on the host — hence the private `_Logger` in the original error text
rather than `zonai_logger`'s `Logger`. `mailman.dart` and `zonai_db.dart`
both already import that library `hide logger` for exactly this collision;
`courier.dart` never got the same treatment. The request-path scope was
never missing.

**Fixed** (2026-08-12): `courier.dart` now imports the barrel `hide logger`
plus `../deps/logger.dart`, so the call reaches `zonai_logger`'s `Logger`
via `loggerProvider`. That provider reads with no `orElse`, so swapping the
silent logger for it would otherwise risk trading the missing warning for a
`StateError` on a future nobody awaits — `loggerProvider` was therefore
added to `ZonaiDb._run`'s (and `_runStream`'s) `includeIfAbsent` set, which
falls back to a default `Logger` (info level, warnings to stderr) rather
than to silence or a crash if a caller registered none. The other route to
`_send`, `mailman.dart`'s `SendEmailRequest` branch, is reached from a
stdout listener registered in `_start`, which reads the same
`loggerProvider` on its normal path before subscribing — so that scope is
established by construction.

Regression coverage in `apps/zonai/test/src/email/courier_test.dart`
asserts the warning **text** reaches a captured logger sink, not merely that
the call does not throw: a no-op logger passes "does not throw" perfectly,
which is how this survived from 2026-07-31.

**Still open for `override_canvas`**: `apps/website`'s forgot-password UI was written against the correct client-side contract (`POST /auth/reset-password` then `POST /auth/confirm`, per `zonai_client`'s `Auth.sendResetPassword`/`Auth.confirm`). This entry claimed the feature could not be exercised end to end on the strength of the crash; the crash has been gone since 2026-07-31, so that claim is unverified rather than known-true. Whether the flow works today is a check for whoever has that repo.

**How to verify a fix**: repeat the exact reproduction above (no `AppConfig.email` set) and confirm the request returns whatever the *intended* success response is (the `sendResetPassword` client call is `Future<void>`, no body expected) with a real "warning logged" line in the server's own log — then separately confirm the same call with a real, working SMTP config actually delivers the email.

## 9. `zonai serve` spontaneously dies after a short idle gap — not tied to any request, not a multi-instance artifact

**Severity: makes any real deployment unusable.** Found 2026-07-26 while manually driving `override_canvas`'s organization-collaborators feature end to end against a real running server (not via the automated test suite, which never hits this — its requests fire back-to-back with no gap, and every test file finishes well inside whatever window this needs to trigger).

**The symptom**: after serving normally for a few seconds — including handling real requests successfully — the process exits on its own. The only output, ever, is:

```
Serving at http://:::PORT/
Access the UI at http://:::PORT/_
Unexpectedly failed to make connection to Revali (server)
```

No stack trace, no earlier warning. `curl .../health` goes from `200` to connection-refused, and the OS process itself (tracked by PID, checked with `kill -0`, not just the HTTP port) is gone.

**Explicitly ruled out, not just assumed:**

- **Not multiple concurrent `zonai serve` instances** (a real, documented issue elsewhere in this repo's `apps/server/README.md` — IPC cross-talk past ~2-3 concurrent instances). Verified clean before and during every repro: `ps aux` showed zero other `zonai`/worker processes anywhere on the machine, `lsof -i :<port>` showed nothing else bound to the port in use, no stray `ServeLock` files. Tracked the single PID directly with `kill -0` on a 1-second cadence alongside HTTP health checks — it dies alone, in isolation, every time.
- **Not the sandbox/harness reaping background processes.** A trivial `for i in 1..60; do sleep 1; done` background job in the exact same environment ran uninterrupted the whole time.
- **Not the dev-mode file watchers or keyboard input listener** (`extensions.watch()`, `rules.watch()`, `rateLimitsCompiler.watch()`, `cronsCompiler.watch()`, `config.watch()`, `operations.watch()`, `keyboardInput.watch()` — all gated behind `if (args.release) return;`, per `serve.dart`/`extensions.dart`/`keyboard_input.dart`). Re-ran with `--release` explicitly passed: still dies, just survives a bit longer (~30s vs. ~5-10s without it).
- **Not tied to request content.** Reproduces with zero application (`/db`, `/auth`) traffic at all — plain repeated `/health` polling is enough exposure, and busier polling measurably extends (but doesn't prevent) time-to-death, which reads as "some activity resets a timer, but something still eventually fires and kills the process."

**Where the log line comes from** (confirmed by reading source, not guessed): `logger.error('Unexpectedly failed to make connection to Revali (server)')` at `apps/zonai/lib/src/db_mutator/revali.dart:223`, inside `_checkHealth`'s exhausted-attempts branch (200 attempts × 100ms = up to 20s of polling `health()` before giving up). That function is called from `_startCompiled` (`revali.dart:~135`), which on failure runs `await stop()` — closing the real `_httpServer` and killing `_process`. **Not isolated**: what re-invokes `Revali.start()`/`_checkHealth()` a second time, well after the first (successful) startup already returned `true` and served real traffic. The only direct caller of `revali.start()` found by inspection is the one-time call in `serve.dart:78`; no `Timer.periodic`, second `start()`/`_checkHealth()` call site, or heartbeat/liveness mechanism was located in the time spent looking. Worth checking: whether `ServeLock`/`kill` (`apps/zonai/lib/src/utils/serve_lock.dart`, `../deps/kill.dart`) or something in the resqlite/native layer schedules any idle-based self-check that isn't gated by `args.release`.

**Suggested next step for whoever picks this up**: reproduce with `dart run` (not the compiled binary) so a debugger/breakpoint can catch the *second* call into `Revali.start()`/`_checkHealth()` directly — grep alone didn't find it, so it's likely reached through an interface/callback rather than a direct call. A minimal repro: `zonai serve --release --port <p>` in a scratch dir (same shape as `apps/server/test/integration/*`'s scratch setup — only `.zonai/executables`/`.zonai/lib`/`.zonai/migrations`/`zonai.yaml`, no raw `lib/` source), confirm `/health` is `200`, then do nothing for 60 seconds and confirm the process (via PID, not just the port) is still alive.

**How to verify a fix**: same repro as above — `zonai serve` (with or without `--release`) should survive an arbitrarily long idle period between requests with no crash, matching how a real, lightly-used production deployment actually behaves.

## 8. `get.*`/`AuthOperations.addClaims` deadlock the issuing worker if that worker is itself mid-request — "unsafe reentrant IPC," not just "slow"

**Severity: silently breaks every request through the affected worker, not just the one that triggered it.** Found 2026-07-26 while building `override_canvas`'s organization-collaborators feature (a row needing to check "does the caller have access to this *other* table's row" as part of its own access decision). Not caused by or specific to that feature — it's a property of the generic `get`/`mutate` IPC mechanism (`libs/zonai_schema/lib/src/handlers/messages/deps/__get.dart`, wired up generically in `message_handler.dart`) combined with how every worker type (rules, operations, extensions, cron) shares the exact same `MessageHandler` request/reply loop.

**Protocol note (2026-07 update):** process Mailman IPC is now **length-prefixed MessagePack** (not JSON lines). Ops/rules on the default project-binary path run **in-process** (no Mailman hop), which avoids this class of nested-channel bug for those layers; the issue remains relevant for extensions/config/crons and for `ZONAI_FORCE_WORKERS=1`.

**The reproduction, in two independent forms:**

1. A row rule calling `get.*` to look up a *different* table, where the caller is itself in the middle of answering an incoming `RowRulesRequest`:
   ```dart no-analyze
   // OrganizationCollaboratorRowRules.canCreate
   Future<bool> canCreate(Jwt? jwt, OrganizationCollaborator row) async {
     final organization = await get.one(tableName: 'organizations', where: Eq('id', row.organizationId.value), jwt: CronJwt());
     return organization != null && organization['owner_id'] == jwt?.userId.value;
   }
   ```
   Every request to `POST /db` on ANY table failed with the rules worker logging:
   ```
   [RULES_EXE]: Received response for unknown request: response/.row.can_access
   ```
2. `AuthOperations.addClaims` calling `get.many` while answering an incoming `GetJwtConfigOperationRequest` (fired on every sign-up/sign-in/refresh):
   ```dart no-analyze
   @override
   Future<Claims> addClaims({required Jwt jwt}) async {
     final owned = await get.many(tableName: 'organizations', where: Eq('owner_id', jwt.userId.value), jwt: CronJwt());
     return Claims({'ownedOrganizationIds': [for (final r in owned ?? const []) r['id'] as String]});
   }
   ```
   Broke *every* sign-up and sign-in in the whole app (not just requests touching organizations), logging:
   ```
   [OPERATIONS_EXE]: Received response for unknown request: response/.auth.get_jwt_config
   ```

Both cases: the worker is currently handling an incoming request it must eventually reply to (`RowRulesRequest`/`GetJwtConfigOperationRequest`), and while handling it, issues its *own* outgoing request (`get.one`/`get.many` → `GetRecordRequest`) back to the host through the same stdin/stdout channel. The reply that comes back gets misattributed to the wrong pending request — the error names the *original incoming* request's own path (`.row.can_access`, `.auth.get_jwt_config`), not the nested one, suggesting the host/worker's reply-correlation gets confused the moment a worker has both an unanswered incoming request and an outstanding outgoing one at the same time.

**What is *not* affected, confirmed by contrast**: `get.one`/`get.many` called from inside an **Extension**'s `beforeCreate` (e.g. `RecordingExtensions.beforeCreate`, `AssetExtensions.beforeCreate`, `OrganizationCollaboratorExtensions.beforeCreate`) works reliably — used successfully throughout this whole session, dozens of passing tests, including immediately after the two bugs above were found and worked around. `beforeCreate` is structurally the same shape (an incoming `CreateExtensionRequest` needing a reply, with a nested outgoing `get.one` mid-handling), so the safe/unsafe boundary isn't simply "hook type" — it may be specific to the `RowRulesRequest`/`GetJwtConfigOperationRequest` request paths, or to rules/operations workers specifically vs. extensions workers; not fully isolated here. `mutate.*` (fire-and-forget, no reply awaited — confirmed via the existing `CleanupExpiredRecordingsCron`) was not implicated either way, since it doesn't wait on a nested reply.

**Not fixed here.** Worked around in `override_canvas` by not doing this at all: `OrganizationCollaboratorRowRules`/`OrganizationRowRules`/`ClientAppRowRules`/`RecordingRowRules` only do synchronous comparisons against `jwt`/the row's own already-attested fields (the same self-attested-then-extension-verified pattern `Recording.ownerId` already used), and the `addClaims` experiment was reverted entirely. This closed off a legitimate use case (row rules deciding access based on a separate table, e.g. a dynamic collaborator list) without a live lookup or JWT claim.

**Suggested fix, for whoever picks this up**: audit `MessageHandler`'s `_pendingHostReplies` bookkeeping (`handlers/messages/message_handler.dart`) for a case where a worker sends an outgoing request *while* an incoming request's own handler is still running — confirm whether replies are correlated purely by request id (as the data structure suggests they should be) or whether some part of the pipeline assumes at most one in-flight conversation per worker. A minimal repro harness: a single-file rules-worker test that does `get.one` on an unrelated table from inside `canView`, hit with concurrent `/db` traffic against two different tables, asserting no `unknown request` log lines appear.

**How to verify a fix**: re-add `get.one`/`get.many` to a row rule (or `get.many` to `addClaims`) and confirm real, concurrent request traffic through that worker no longer logs `Received response for unknown request`.

## 7. No CORS support anywhere — a standalone frontend on a different origin from the server cannot call it from a real browser

**Update 2026-07-26: fixed.** Confirmed via a real preflight against the
compiled `apps/server` binary — `OPTIONS /db` and `OPTIONS /db/list` with
`Origin: http://localhost:3000` (override_canvas's `apps/website`, a
genuinely different origin from the server's `:8080`) both return `200`
with `access-control-allow-origin: http://localhost:3000`,
`access-control-allow-methods`, `access-control-allow-headers`, and
`access-control-allow-credentials: true`. `apps/website`'s dashboard sign-in
flow (browser, not curl) round-trips correctly against a server on a
different port with this fix in place. Not re-run against the original
"zero hits" grep to find exactly where this landed; left below for history.

**Severity: blocks a whole class of deployment** (any frontend that isn't served from the exact same origin as the zonai server) **— not caused by, or specific to, any one endpoint.** Found 2026-07-25 while building `override_canvas`'s asset-resolution-during-replay feature, but it applies to every browser-side call any external frontend makes to zonai — sign-in, generic `/db` CRUD, everything.

**The fact itself, confirmed by reading the source, not assumed:**

```
grep -rn "Access-Control-Allow-Origin\|cors\|Cors\|CORS" apps/server/ apps/zonai/lib/
# zero hits
```

No lifecycle component, middleware, or route anywhere sets any `Access-Control-*` response header. Combined with the universal, standard behavior of every real browser (block a cross-origin `fetch`/`XMLHttpRequest` response from being read by the calling page unless the response carries a matching `Access-Control-Allow-Origin` header — this is not zonai-specific, it's the same-origin policy every browser enforces by default), the conclusion follows without needing to reproduce it live: **any web app served from a different origin (different scheme, host, or port) than the zonai server it talks to will have every one of its API calls blocked by the browser**, regardless of whether the request itself is otherwise perfectly valid — confirmed working fine via `dart:io`-based HTTP clients (curl, Dart VM tests) throughout this session, which is precisely why this went unnoticed: none of those tools are subject to CORS at all, only real browser `fetch()`/`XMLHttpRequest` calls are.

**Why this matters for zonai specifically, not just this one app**: zonai's own docs and examples (`apps/web`, the internal Jaspr dashboard) work today because that frontend is served *by the same server process* it calls — same origin, CORS never enters the picture. But nothing about zonai's actual architecture requires that pairing, and `docs/`'s own framing of "batteries included" backend implies external, independently-hosted frontends are a legitimate use case — override_canvas's `apps/website` is exactly that: a deliberately standalone Jaspr site talking to a separately-deployed zonai server. That combination is silently broken in any real browser today.

**Not attempted here** — this needs real design care, not a quick patch: a naive `Access-Control-Allow-Origin: *` is the common quick fix, but would need auditing against zonai's actual credential model first (this app uses bearer tokens in an `Authorization` header rather than cookies, which meaningfully narrows the usual wildcard-CORS risk profile — a wildcard origin is a real problem specifically for cookie/credentialed requests, less so for header-based bearer auth — but that's a judgment call for whoever actually implements this, not confirmed safe here). At minimum needs: a configurable allowed-origins list (not hardcoded), correct handling of preflight `OPTIONS` requests (not just the actual response), and a decision on whether it's a `LifecycleComponent`/guard (per issue #1's fix) or a different mechanism entirely.

**Workaround for now**: deploy the frontend and the zonai server behind the same origin (a reverse proxy routing `/api/*` to zonai and everything else to the static frontend, for example) — same-origin requests are never subject to CORS regardless of this gap.

## 6. `AsAdmin` grants admin rights to *every account on the table*, not the specific accounts created via `zonai db admin add` — docs fixed, this is a real design footgun to know about

**Severity: critical, if you follow the docs' own primary example as written.** Found 2026-07-25 while adding an admin schema for `override_canvas`, by literally following `docs/rules/jwt-claims.md`'s own example (`with PasswordAuth, AsAdmin` on the app's regular `UserTable`) and then testing the result against a real running server before trusting it.

**Reproduction:**

```
# Schema: `final class UserTable extends AuthTable<User> with PasswordAuth, AsAdmin { ... }`
# users also supports public sign-up (the normal case for an app's user table)

curl -X POST /auth/sign-up -d '{"type":"signUp","table":"users","email":"brand-new@example.com","password":"...","object":{...}}'
# decode the returned accessToken:
#   "admin": { "isAdmin": true, "canEdit": true }
```

A completely fresh, never-privileged, publicly-self-registered account gets full admin claims. This isn't a corner case — it happens for every account on that table, every time, via every auth flow (sign-up, sign-in, OTP, magic link).

**Root cause.** `libs/zonai_schema/lib/src/handlers/operations/db_operations.dart`'s `_getJwtConfig`:

```dart no-analyze
final admin = switch (ops?.schema) {
  final AsAdmin admin => admin,
  _ => null,
};

return JwtConfigResponse(
  id: request.id,
  config: JwtConfig(
    claims: claims,
    isAdmin: admin != null,           // <-- per TABLE, not per row
    canEdit: admin?.canEdit ?? false,
    expiresIn: expiresIn,
  ),
);
```

`isAdmin` is computed purely from "does this table's schema implement `AsAdmin`" — it has no way to know whether *this specific row* was created via `zonai db admin add` versus a regular sign-up. There is no per-row admin flag anywhere in the design; `AsAdmin` is fundamentally a per-table switch. Every JWT for every row in an `AsAdmin` table gets the same claims, regardless of how that row's account came to exist or which endpoint (`/auth/sign-up`, `/auth/sign-in`, `/auth/admin`, ...) issued the token.

**This makes `AsAdmin` outright unsafe on any table that also accepts public self-registration.** It is only safe on a table dedicated exclusively to admin accounts, where the *only* way a row can ever be created is `zonai db admin add` (which builds/executes SQL directly — see `apps/zonai/lib/src/db_mutator/zonai_db/parts/admin/create_admin.dart` — bypassing rules entirely, so it isn't itself blocked by anything below). Defense in depth still matters: without an explicit `AuthRowRules.canSignUp` override returning `false`, the *public* `/auth/sign-up` endpoint would happily create new rows on that "admin-only" table too (its default `canSignUp` implementation just checks `schema is PasswordAuth`, true for any password-auth table), letting anyone self-register as an admin over HTTP.

**Fixed**: `docs/rules/jwt-claims.md`'s example now uses a dedicated `AdminTable`/`Admin` (not `UserTable`/`User`), states the per-table-not-per-row behavior explicitly up front, and includes the `canSignUp: false` row-rule override as part of the example rather than treating it as optional. **Not fixed** (would be a real, invasive design change, out of scope here): there's no way, as currently designed, to have admin AND non-admin accounts coexist safely in the *same* auth table — if that's ever wanted, `isAdmin` would need to become a real per-row column/claim instead of a per-table marker.

**Fixed again, 2026-08-16 — this time in the framework rather than in the prose.** The paragraph above ends with "without an explicit `canSignUp` override returning `false`, the public `/auth/sign-up` endpoint would happily create new rows on that admin-only table too", and a documented remedy that every app must remember to apply is exactly the kind that gets forgotten. `AuthRowRules.canSignUp` now returns `false` when `schema is AsAdmin`, unless the caller already holds an admin token — so the dangerous combination fails closed, and an app that wants open registration on an admin table has to write the override *to allow* it rather than *to deny* it. Regression tests: `libs/zonai_schema/test/src/rules/auth_row_rules_test.dart`. `zonai db admin create` is untouched (it bypasses rules, as noted above), and the non-`AsAdmin` defaults are unchanged — the tests pin both, since "tighten sign-up for everyone" would be a different and much worse fix.

The design limitation itself is still real: `isAdmin` remains per-table, so admin and non-admin accounts still cannot coexist in one auth table. The new default only removes the silent path from "I added `AsAdmin` for the claims" to "every stranger is an admin".

**How this was confirmed** (not just read from source, and not just theorized): built the vulnerable version first (`with AsAdmin` on a table with public sign-up), started a real compiled server, signed up a brand-new account via `/auth/sign-up`, and decoded its JWT — got `isAdmin: true`. Then rebuilt with a dedicated table instead, re-ran the same sign-up against the same server, and confirmed `isAdmin: false`; separately confirmed a direct `POST /auth/sign-up` attempt against the dedicated admin table (`table: "admins"`) is rejected with `403` once `canSignUp` is overridden. See `override_canvas/apps/server/test/integration/admin_security_integration_test.dart` for the regression tests this produced (regular sign-up/sign-in never get admin claims; self-registration on the admin table is rejected; a CLI-bootstrapped admin account signs in with real admin claims).

## 5. `POST /auth/sign-up` on an existing email silently succeeds if the password happens to match — resolved 2026-08-13 as intended behavior, now documented

> **Root cause found, and both hypotheses below were wrong.** There is no
> `INSERT OR IGNORE`, no upsert, and no catch-and-refetch. Nothing swallows a
> unique-index violation, because the `INSERT` is never attempted.
>
> `/auth/sign-up` and `/auth/sign-in` both funnel into `_authenticate`
> (`parts/auth/auth.dart:50`), whose own doc comment states the design:
>
> ```
> /// Signs in a user if the credentials are valid
> ///
> /// Signs up a user if the record does not exist
> ```
>
> For password auth it delegates to `_authenticatePassword`
> (`parts/auth/password.dart:4`), which branches on **one thing only** —
> whether an auth record already exists:
>
> ```dart no-analyze
> final hasAuthRecord = await _hasAuthRecord(table: table, payload: payload);
> if (!hasAuthRecord) {
>   if (isAdmin) throw UserNotFoundAuthException(table: table);
>   return await _signUpWithPassword(table, payload);
> }
> return await _signInWithPassword(table, payload);
> ```
>
> The payload's *intent* is never consulted. That reproduces every observed
> symptom exactly: the first call creates, the second with the same password
> signs in and returns the same row with a fresh JWT, and the third with a
> wrong password returns sign-in's own 401 "Invalid password or email" —
> which is the tell, since that message belongs to sign-in and was reaching a
> caller who asked to sign up.
>
> **The intent is available and discarded.** `SignUpAuthBody` and
> `SignInAuthBody` are distinct types at the HTTP boundary
> (`auth_password_body.dart:480,517`) reaching distinct controller methods;
> both collapse to a `PasswordAuthPayload` before the decision is made.
>
> **Decided 2026-08-13: this is the intended behavior, and it stays.** Sign-up
> on an existing account signs that account in. It is consistent with what
> magic link and OTP already do in the other direction (create on first use),
> and it makes a retried sign-up safe for clients that resend after a network
> timeout.
>
> So this stops being a defect and becomes an API contract — which means the
> only real problem it ever had, "semantic surprise", is fixed by writing it
> down. Documented in
> `apps/docs/content/authentication/password-auth.md` → *Signing up an email
> that already exists*, including the one thing a client author has to design
> around: **sign-up will not tell you an email is taken**, and a wrong
> password returns the same `401` as a genuinely wrong sign-in, so the
> response cannot distinguish the two.
>
> Changing it later — sign-up 409s on an existing record, sign-in 401s on a
> missing one — is on the backlog (`todo.md`, Auth). It would be a breaking
> change, and the implementation is small: thread the intent through and
> branch on it rather than on existence alone.
>
> Original investigation kept below.

Behavior confirmed via real `curl` calls against a live server (not from reading source), but the exact code path producing it wasn't found in the time spent looking (checked `_signUpWithPassword` in `apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/password.dart` end to end — no explicit "check existing email" or "catch unique-violation, fall back" logic visible there; regular, non-auth `insert()` does not exhibit this — confirmed separately by creating duplicate rows on this session's own `organizations`/`client_apps` tables without issue elsewhere).

**Reproduction:**

```
curl -X POST /auth/sign-up -d '{"type":"signUp","table":"users","email":"a@x.com","password":"P1!","object":{...}}'
# → 200, real new user created

curl -X POST /auth/sign-up -d '{"type":"signUp","table":"users","email":"a@x.com","password":"P1!","object":{...}}'
# → 200, SAME user id/name/created_at as the first response — no second row created

curl -X POST /auth/sign-up -d '{"type":"signUp","table":"users","email":"a@x.com","password":"DIFFERENT","object":{...}}'
# → 401 "Invalid password or email"
```

So a repeated sign-up to an already-registered email is **not** rejected outright — it succeeds (200, fresh JWT) if the submitted password happens to match the existing account's, and only fails if it doesn't. Net effect: `/auth/sign-up` is accidentally usable as a second `/auth/sign-in` for password auth, and (more importantly) a client repeatedly retrying a sign-up call (e.g. on a network timeout, unaware the first attempt actually succeeded) will not get a clear "this email is taken" signal — it'll silently get back the original account instead of an error, which could mask real bugs in retry logic.

**Not a credential-guessing vector**: a caller who doesn't know the real password still gets a normal 401, so this doesn't let anyone into an account they don't have the password for. The main risk is semantic/API-contract surprise, not authentication bypass.

**Suggested next step for whoever picks this up**: trace what actually happens to the `INSERT` when the unique index (`users_email_unique` in this app's own schema — see `override_canvas/apps/server/lib/src/schemas/users.dart`) is violated during a sign-up `CreateAuthOperationRequest`. Given the symptom (silently returns the pre-existing row rather than throwing), the most likely places are (a) something in the create-auth SQL path using `INSERT ... RETURNING` with `OR IGNORE`/upsert semantics specifically for auth creates (regular non-auth `insert()` does **not** default to this — see `raindrop_sqlite`'s `insertOrIgnore`, an explicit opt-in extension method, not the default `insert()`), or (b) a `catch` somewhere between the insert failing and the response being built that re-fetches by email and treats it as success. Neither was confirmed; this needs someone to actually add tracing inside `_signUpWithPassword` and watch it hit the duplicate case, not more guessing from outside.

## 4. `get.one` silently drops its `jwt` parameter — fixed

**Severity: correctness/security** — any extension calling `get.one(..., jwt: someJwt)` to grant a lookup elevated or different access than the calling request's own JWT got the **caller's JWT instead**, silently. Found 2026-07-25 while building `RecordingExtensions.beforeCreate` (an anonymous, API-key-authenticated recording upload that needs to read the owning `client_apps` row — which is rules-gated to authenticated owners — to validate the key).

**Root cause.** `libs/zonai_schema/lib/src/handlers/messages/deps/__get.dart`, `_Get`'s constructor:

```dart no-analyze
_Get(this.many) {
  one = ({required String tableName, required where, offset, jwt}) async {
    final result = await many(
      tableName: tableName,
      where: where,
      limit: 1,
      offset: offset,
      // jwt was accepted here but never forwarded below
    );
    return result?.single;
  };
}
```

`one`'s signature accepts `jwt`, but the body never passes it to `many(...)` — it silently falls through to whatever `many` treats as its default (the calling request's own JWT, effectively ignoring any override).

**How this was confirmed** (not just read from source): passed both a hand-built `Jwt` and a `CronJwt()` sentinel to `get.one(..., jwt: ...)` inside a real extension and printed the JWT actually seen by the rule check on the other end (`ClientAppTableRules.canList`) — logged `jwt=null` every time, matching "caller's real JWT" (an anonymous upload) rather than either override. Fixed by forwarding `jwt: jwt` into the `many(...)` call; re-ran `dart analyze`/`dart test` on `libs/zonai_schema` — clean, no regressions (149/149 passing).

**Practical impact**: any extension trying to do a privileged/differently-scoped internal read via `get.one(jwt: ...)` — e.g. to check something the calling request itself isn't authorized to see directly — silently got the caller's own (often more restrictive, sometimes `null`/unauthenticated) access instead, with no error to indicate the override didn't apply. `get.many` does **not** have this bug — it forwards `jwt` correctly; only the `one` wrapper built on top of it does not.

## 3. `implements Id` classes have broken value equality — fixed for `UnknownId`; still open for the rest

**Severity: correctness, was silently breaking real ownership checks.**
Found 2026-07-25 while adding ownership rules for a scratch table (own
work, not a hand-off item, but recording it here since it's the same
"real pre-existing bug found along the way" category as #1/#2).

`Id` (`libs/zonai_schema/lib/src/types/id.dart`) declares `operator==`/
`hashCode` with real bodies, but every implementer (`UnknownId`, `PhotoId`,
`AbuserId`, `JwtId`, and others — anything doing `implements Id`) does
**not** inherit those bodies: Dart's `implements` only takes on a class's
member *signatures*, never its concrete implementations (that only happens
through `extends`/mixins). Without its own override, an implementer falls
back to `Object`'s identity-based equality. Confirmed empirically (a
throwaway test, not just reading the spec): two separately-constructed
`UnknownId('user_123')` instances compared unequal.

**Practical impact, not just theoretical**: `PhotoRowRules.canUpdate`/
`canDelete` (`libs/zonai_schema/lib/src/internal/rules/photo_row_rules.dart`)
check `jwt.userId == row.ownerId` — both sides are `UnknownId`, built down
two completely different paths (JWT claim decode vs. a DB row read), so
they're never the same object instance. This means that check has
presumably **always evaluated false for the real, legitimate owner** —
a photo's actual owner could never update or delete their own photo via
the generic path. Not verified against a live request (no repro server
run), but the equality behavior itself is directly confirmed.

**Fixed**: `UnknownId` (the class actually used for cross-entity
ownership comparisons everywhere) now has a real `operator==`/`hashCode`.
**Deliberately not fixed**: `PhotoId`, `AbuserId`, `JwtId`, and any other
pre-existing `implements Id` class — same latent bug, but none of them are
compared for equality directly in real logic the way `UnknownId` is
(they're used as primary keys / `.where(column.equals(id))` query values,
which compare via the underlying column value in SQL, not Dart `==`), so
fixing `UnknownId` closes the actually-exercised gap without a broader,
riskier sweep through every internal table file. Worth a full audit at
some point regardless — grep for `implements Id`. Also worth noting: don't
assume "never compared directly" holds forever for a given ID type — it
only takes one new piece of code doing a direct `==` comparison (instead of
going through a query builder's `.equals()`) to turn this into a live bug
for that type too, so re-check this assumption whenever a new direct
comparison shows up on an `implements Id` type.

Regression coverage: `libs/zonai_schema/test/src/types/id_test.dart` —
uses runtime-constructed (non-`const`) instances deliberately, since
`const UnknownId('x')` literals get canonicalized by the compiler and
would accidentally pass via identity even with the bug still present.
Confirmed via deliberate revert that these tests fail without the fix.

## 1. `@BlackList()` generates no guard at all — every annotated controller is currently unprotected — fixed

> **Fixed, and re-verified 2026-08-13.** `BlackList` now
> `implements LifecycleComponent`, and all five generated route files list
> `guards: [BlackListGuard(di)]` — checked directly in
> `apps/zonai/lib/gen/server/.revali/server/routes/` for `__auth_route`,
> `__db_route`, `__email_route`, `__img_route` and `__r1_route`, which is the
> verification this entry asked for.
>
> The gap that remained after the code fix was the one predicted below: no
> test could catch a regression, because removing the `implements` clause
> compiles cleanly and only stops producing generated output nobody reads.
> `apps/server/test/lifecycle_component_wiring_test.dart` now pins it, and was
> confirmed to fail with the clause removed rather than merely to pass with it
> present. It does **not** assert that a blacklisted IP is rejected at
> runtime — that needs a live server and a seeded `abusers` row.
>
> Original diagnosis kept below.

**Severity: security.** Five controllers declare `@BlackList()` expecting
IP-based abuse blocking, but the annotation is never actually wired up as a
guard by Revali's code generator — it is silently a no-op. Confirmed via the
generator source and by inspecting a generated route file; this is not a
runtime/config issue, it cannot work as currently written.

**Affected controllers** (`apps/server/routes/controllers/`):
- `web_controller.dart`
- `email_controller.dart`
- `photos_controller.dart`
- `auth_controller.dart` — most severe: sign-in/sign-up/refresh/reset-password all currently have zero IP-based abuse protection
- `db_controller.dart` — the generic CRUD surface, also currently unprotected

**Root cause.** `BlackList` (`apps/server/routes/components/black_list.dart`):

```dart no-analyze
final class BlackList {
  const BlackList();

  Future<GuardResult> check(@Ip() String ipAddress) async { ... }
}
```

has the right shape (a `check` method returning `Future<GuardResult>`), but
the class does **not** `implement LifecycleComponent`
(`package:revali_router_annotations`). Revali's server generator only
recognizes an annotation instance as contributing a lifecycle
component/guard when its static type matches that marker — see
`ServerRouteAnnotations._fromGetter` in the resolved `revali_server`
package (pinned via this workspace's `pubspec_overrides.yaml`, currently
`~/.pub-cache/git/revali-c89dd3ed.../constructs/revali_server/lib/converters/server_route_annotations.dart:158`):

```dart no-analyze
OnMatch(
  classType: LifecycleComponent,
  package: 'revali_router_annotations',
  convert: (object, annotation) {
    lifecycleComponents.add(
      ServerLifecycleComponent.fromDartObject(object, annotation),
    );
  },
),
```

Since `BlackList`'s type never matches `classType: LifecycleComponent`,
`@BlackList()` never reaches this `OnMatch` branch, so it contributes
nothing to `lifecycleComponents` — no guard is ever registered for any
controller annotated with it.

**How this was confirmed** (not just read from source): added a scratch
guard that *does* `implements LifecycleComponent`. Regenerating `.revali/`
twice — once with the scratch guard also missing the `implements` clause,
once with it added — showed the generated route only ever lists a
`guards: [...]` entry in the second case. The exact same experiment applied
to `BlackList` would show the same absence for every controller listed
above; this wasn't repeated here to avoid making an unrelated,
broader-blast-radius change while investigating.

**Suggested fix.** In `apps/server/routes/components/black_list.dart`
(`no-analyze`: the import is a placeholder and the bodies are elided, so this
sketch is deliberately not compilable — see the note after it):

```dart no-analyze
import 'package:revali_router_annotations/revali_router_annotations.dart'; // or wherever LifecycleComponent is exported from for this workspace's pinned revali version

final class BlackList implements LifecycleComponent {
  const BlackList();

  Future<GuardResult> check(@Ip() String ipAddress) async { ... } // unchanged
}
```

Then regenerate `.revali/` (check `apps/docs/content/*`/root
`docs/GET_STARTED` for the documented codegen step) and confirm each of the
five generated route files above now lists `BlackListGuard(...)` (or
equivalent) in its `guards: [...]`.

**How to verify the fix**: write or extend a route-level test (or a
generated-route inspection, matching how this was confirmed above) that
asserts a request from a row in `abusers` with `blackListed: true` is
actually rejected with `403` on at least one of the five affected
endpoints — today, no such test would catch this, since the annotation
compiles fine and only silently fails to do anything at request time.

## 2. `raindrop_cli`'s migration generator can't resolve schemas outside the calling package

**Severity: blocks migrations for any table added to `zonai_schema`** — this
reproduces for the *first* table the loader tries to resolve regardless of
which table you're actually trying to add.

**Reproduction** (safe to re-run — fails before writing any file, no `.sql`/
journal/snapshot is created, no database is touched):

```
cd apps/zonai
dart run tool/generate_internal_db_artifacts.dart --migrate --name <anything>
```

```
Unhandled exception:
Bad state: Unable to find the context to /Users/morgan/Development/dart_projects/zonai/libs/zonai_schema/lib/src/internal/tables/abusers_table.dart
#0      AnalysisContextCollectionImpl.contextFor (package:analyzer/src/dart/analysis/analysis_context_collection.dart:157:5)
#1      discoverSchemaVariables (package:raindrop_cli/src/runtime/schema_table_discovery.dart:54:32)
#2      RuntimeSchemaLoader.load (package:raindrop_cli/src/runtime/runtime_schema_loader.dart:27:29)
#3      GenerateCommand.run (package:raindrop_cli/src/cli/commands/generate.dart:92:51)
```

(The non-`--migrate` path, `dart run tool/generate_internal_db_artifacts.dart`
with no flag, works fine — it doesn't go through this analyzer-based
schema loader.)

**Root cause.** `apps/zonai/raindrop.yaml`:

```yaml
schemas: ../../libs/zonai_schema/lib/src/internal/tables
```

points outside `apps/zonai`'s own directory (into the sibling `libs/`
package where all schema/table definitions actually live — see
`libs/zonai_schema`'s own description: "Shared relational model for
Zonai... anything else clients and services need to agree on the DB
shape"). `RuntimeSchemaLoader.load` (`libs/raindrop/packages/raindrop_cli/lib/src/runtime/runtime_schema_loader.dart:27-30`) passes the *project* root
(`apps/zonai`) as `packageRoot` and the resolved `schemas:` path as
`schemaDir` into `discoverSchemaVariables`, which then does
(`libs/raindrop/packages/raindrop_cli/lib/src/runtime/schema_table_discovery.dart:49-54`):

```dart no-analyze
final absRoot = p.normalize(p.absolute(packageRoot)); // apps/zonai only
final collection = AnalysisContextCollection(includedPaths: [absRoot]);
...
for (final path in dartFiles) { // dartFiles come from schemaDir, e.g. libs/zonai_schema/...
  final context = collection.contextFor(path); // throws: path isn't under absRoot
  ...
```

`AnalysisContextCollection` is only told about `apps/zonai`; every file
under `schemaDir` (`libs/zonai_schema/...`) is outside that root, so
`contextFor` throws for the very first file it processes — this has
nothing to do with which table is being added, it would fail identically
for any table.

**Suggested fix.** Include both roots (deduplicated) in
`schema_table_discovery.dart`:

```dart no-analyze
final absRoot = p.normalize(p.absolute(packageRoot));
final absSchemaRoot = p.normalize(p.absolute(schemaDir));
final includedPaths = {absRoot, absSchemaRoot}.toList();
final collection = AnalysisContextCollection(includedPaths: includedPaths);
```

This is additive — the common case where `schemaDir` is already nested
inside `packageRoot` just gets a harmless duplicate-ish root; the
cross-package case (this repo's actual layout) gets the root it's
currently missing. `libs/raindrop` is a git submodule (fork of
`wolfenrain/raindrop`, branch `zonai`) — this fix belongs there, then
needs the submodule pointer bumped in this repo once merged.

**How to verify the fix**: re-run the exact reproduction command above
from a clean checkout after the fix; it should get past schema discovery
and actually produce a `.sql` migration file for whichever table triggered
it, under `apps/zonai/lib/src/internal/migrations/`.
