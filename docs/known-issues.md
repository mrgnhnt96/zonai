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

```dart
'INSERT INTO $temp SELECT * FROM $table;',
```

`$temp`'s `CREATE TABLE` (line 132: `tableColumns.map(_columnDefinition).join(...)`) is built from `tableColumns` — the schema's own declared/sorted column order — but `$table`'s actual on-disk physical column order can diverge from that the moment any column was ever added via `alterColumn`'s sibling `addColumn` path (a plain `ALTER TABLE ADD COLUMN`, which SQLite always appends physically regardless of where the column sits in the schema's declared order). `SELECT *`/bare `INSERT INTO` both resolve by *position*, not name, so once the two orders diverge, every column from the divergence point on gets inserted into the wrong slot.

**Worked around, not fixed here** (in `override_canvas`, not this repo): hand-edited the two pending migration files to use explicit, name-matched column lists on both sides of the `INSERT`/`SELECT` instead of relying on position — safe to do only because neither migration had ever actually been applied anywhere yet (confirmed via the `_raindrop_migrations` tracking table). This is a per-migration-file workaround; every future `alterColumn` rebuild on a table with this history will hit the same bug again until it's fixed at the source below.

**Suggested fix**, in `_rebuildTableFromAlters` (`sqlite_ddl.dart`): build the `INSERT`/`SELECT` from `tableColumns` explicitly, the same list already used to build `defs`, instead of `SELECT *`:

```dart
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

## 10. `POST /auth/reset-password` crashes with an uncaught scoping error whenever email isn't configured — not a graceful skip like the docs describe

**Severity: breaks password reset outright for any app without SMTP configured**, which is presumably the common case for local dev and any fresh deployment before email is wired up — `docs/email.md` explicitly documents "If `AppConfig.email` is missing, send attempts are skipped and a warning is logged," which is not what actually happens. Found 2026-07-26 while adding a "forgot password" flow to `override_canvas`'s `apps/website`.

**Reproduction** (against a real compiled `apps/server` binary with no `AppConfig.email` set, which is this app's actual current config):

```
curl -X POST /auth/reset-password -d '{"type":"sendResetPassword","table":"users","email":"real@example.com"}'
# → empty response, connection dropped

# server log:
Bad state: read(ScopedRef<_Logger>) was called in a scope which does not contain a corresponding value for the provided ref.
Did you forget to call: runScoped(() {...}, values: {value})?
Unhandled error while serving (process continues)
```

A second identical request within 60 seconds gets a normal `{"error":"Must wait 60 seconds before sending a new code"}` — confirming the *first* request's core logic (creating the `authChallenges` row, rate-limit bookkeeping) succeeds; the crash happens strictly *after* that, in the code path that's supposed to just warn-and-skip the actual email send.

**Root cause**, `apps/zonai/lib/src/email/courier.dart`'s `_Send._send`:

```dart
Future<void> _send(Email email) async {
  final config = await configResolver.resolve();
  final emailConfig = config.email;
  if (emailConfig == null) {
    logger.warn('Cannot send email because email configuration is missing');  // <-- throws
    return;
  }
  ...
```

`logger` here is a `scoped_deps` reference requiring `runScoped(..., values: {loggerRef: ...})` to have been set up somewhere up the call stack in the *current* execution context — this works fine from other paths that already print to this same server's log (e.g. this session's own cron output, `[CRON] started: _delete_old_rate_limits`), so the scope itself is real and set up correctly for at least some worker/handler contexts. It is specifically **not** set up for whatever context invokes `courier.send` from `_sendResetPassword` (`apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/reset_password.dart`) when reached via the real `/auth/reset-password` route — not isolated further than that (didn't trace which handler/worker owns this request path or where its `runScoped` wrapper should be, or already is, established).

**Not fixed here.** `apps/website`'s forgot-password UI was written against the correct client-side contract (`POST /auth/reset-password` then `POST /auth/confirm`, per `zonai_client`'s `Auth.sendResetPassword`/`Auth.confirm`) but the feature cannot actually be exercised end-to-end in this app until either this is fixed or real SMTP is configured (unconfirmed whether configuring email avoids this specific branch entirely, since the crash is *in* the missing-config branch specifically — if it's a wave-through-once-you-add-email bug, that would only mask it for configured deployments, not fix the "docs promise a graceful skip, code doesn't deliver one" gap for everyone else).

**How to verify a fix**: repeat the exact reproduction above (no `AppConfig.email` set) and confirm the request returns whatever the *intended* success response is (the `sendResetPassword` client call is `Future<void>`, no body expected) with a real "warning logged" line in the server's own log instead of the scoping crash — then separately confirm the same call with a real, working SMTP config actually delivers the email.

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
   ```dart
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
   ```dart
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

```dart
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

**How this was confirmed** (not just read from source, and not just theorized): built the vulnerable version first (`with AsAdmin` on a table with public sign-up), started a real compiled server, signed up a brand-new account via `/auth/sign-up`, and decoded its JWT — got `isAdmin: true`. Then rebuilt with a dedicated table instead, re-ran the same sign-up against the same server, and confirmed `isAdmin: false`; separately confirmed a direct `POST /auth/sign-up` attempt against the dedicated admin table (`table: "admins"`) is rejected with `403` once `canSignUp` is overridden. See `override_canvas/apps/server/test/integration/admin_security_integration_test.dart` for the regression tests this produced (regular sign-up/sign-in never get admin claims; self-registration on the admin table is rejected; a CLI-bootstrapped admin account signs in with real admin claims).

## 5. `POST /auth/sign-up` on an existing email silently succeeds if the password happens to match — not fixed, root cause not isolated

**Severity: unclear, worth a closer look** — behavior confirmed via real `curl` calls against a live server (not from reading source), but the exact code path producing it wasn't found in the time spent looking (checked `_signUpWithPassword` in `apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/password.dart` end to end — no explicit "check existing email" or "catch unique-violation, fall back" logic visible there; regular, non-auth `insert()` does not exhibit this — confirmed separately by creating duplicate rows on this session's own `organizations`/`client_apps` tables without issue elsewhere).

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

```dart
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

## 1. `@BlackList()` generates no guard at all — every annotated controller is currently unprotected

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

```dart
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

```dart
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

```dart
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

```dart
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
