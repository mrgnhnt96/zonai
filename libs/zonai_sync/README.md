# zonai_sync

Offline-first sync for Dart and Flutter apps on a [Zonai](https://zonai.dev) backend.

The device's local database is the source of truth. The app reads and writes it
without waiting on the network. `SyncEngine` keeps it in step with the server: a
transactional outbox pushes local changes, and scoped cursor pulls bring back what
changed elsewhere. Conflicts are settled by server revision, never by comparing
device clocks.

> Status: `0.1.0-dev`. Works against zonai 0.9.4 today. It will adopt server-side
> scoping, precondition responses and revision/sequence columns as they land in core.

## Why a library

Every app that syncs with zonai by hand runs into the same zonai behaviours. Each
of the following is a shipped bug this engine avoids by construction:

| Behaviour | How the engine handles it |
|---|---|
| A nullable `updated_at` is `NULL` on insert, so `updated_at > cursor` never sees rows that were never edited | the first pull starts from nothing, and the adapter refuses a synced table without a non-null `updated_at` |
| A list returns 403 for the whole request if any one row fails `canView` | every pull of an owned table carries `owner = me` |
| Table-level `canUpdate` is checked before the row lookup, so update-then-create 403s on new rows | new rows are pushed as creates; a 409 falls back to reconciliation |
| The server ignores client-written `updated_at`, so comparing it against the server's is comparing two clocks | conflicts are decided by `rev`, a server-side revision |
| Nobody owns "whose data is on this device" | a different account clears rows, outbox and cursors first, atomically |

## Use

```dart
final sync = SyncEngine(
  remote: ZonaiSyncRemote(zonaiClient),
  local: myStore,                       // a SyncLocalStore (drift adapter, or MemorySyncStore)
  tables: const [
    SyncTable('courses'),
    SyncTable('students', parents: ['courses']),
    SyncTable('evaluations', parents: ['students'], conflict: ConflictPolicy.fieldMerge),
  ],
  account: () => currentUserId,
);

sync.start();                              // periodic reconcile + an immediate pass
await sync.write('courses', {'id': id, 'owner_id': me, 'name': 'Biology'});
await sync.delete('courses', id);          // a tombstone
sync.status.listen(render);                // pending, dead letters, phase
await sync.signOut();                      // erases everything for this account
```

Call `sync.requestSync()` on connectivity changes, on app resume and on live-query
pokes. A request that arrives mid-sync schedules another pass; it is never
dropped. Every request times out after `requestTimeout` (30s by default) and
counts as offline.

Synced rows travel through the outbox as JSON, so their values must be
JSON-encodable: send dates as epoch milliseconds and bytes as base64, not
`DateTime` or `Uint8List`.

The library imports no `dart:io`, so it builds for Flutter web.

## Server table requirements

Declare these columns on every synced table:

- `updated_at`: `$.updatedAt(...)` with a **non-nullable** `DateTime` field, so
  zonai stamps it on insert as well as on update.
- `rev`: an `int` column. The client conditions every update on it. On a
  server with `$.revision()`, move tables to it one by one: deploy the server
  change for a table first, then ship a client that lists the table in
  `ZonaiSyncCapabilities(serverRevisionTables: {...})`. A migrated table
  refuses a client-sent `rev` with a 400.
- `deleted_at`: a nullable `DateTime`, the tombstone. Deny hard deletes in the
  row rules.
- An owner column (default `owner_id`). Row rules check it on `canView`,
  `canCreate`, and **both sides** of `canUpdate`.
- Table rules allow `canUpdate` for signed-in users, so the row rules decide.

`e2e/sync` in this repo is a complete, working example.

Until `$.revision()` is deployed, `rev` only moves when a write goes through
zonai_sync. A write that bypasses it (the dashboard, another client) leaves
`rev` alone, and the next synced update of that row silently overwrites it.

## Conflict policies

| Policy | On a revision conflict |
|---|---|
| `ConflictPolicy.fieldMerge` (default) | re-applies only the fields changed locally, so edits to different fields both survive |
| `ConflictPolicy.serverWins` | adopts the server row and drops the local change |
| `ConflictPolicy.clientWins` | re-applies the whole local row |
| `CustomMerge((local, server, changedFields) => ...)` | your function decides |

## Failures

| Server says | Engine does |
|---|---|
| offline, timeout | keeps the change queued without spending a retry attempt, and tries again after `offlineRetry` (30s) |
| 401 | pauses (`SyncPhase.needsAuth`). Nothing retries it: sign the user in again, then call `resume()` |
| 403, 400, 422 | dead-letters it: visible in `status.deadLetters`, with `retryDeadLetter`/`discardDeadLetter` |
| 409 on create | reconciles with the existing row |
| 412 / revision mismatch | applies the table's conflict policy |
| 429 | waits for `retryAfter`, then retries on its own |
| 5xx | backs off exponentially and retries on its own when the delay ends; dead-letters after `RetryPolicy.maxAttempts` |

### Parents and children

A child is never sent while its parent is still waiting to reach the server
(backing off, or itself held). How precisely depends on whether the child's
table declares `references`:

- **With `references`** (`{'course_id': 'courses'}`), holding is per row: only
  the children of the stuck parent row wait, including when that parent is
  dead-lettered, and the hold carries on to grandchildren.
- **Without `references`**, holding is per table: any waiting row in an
  ancestor table holds the whole child table. A dead-lettered parent does
  **not** hold the child table, which would freeze it indefinitely. On zonai,
  a child of that dead parent gets a 422 (`ForeignKeyConstraintException`) and
  becomes its own dead letter, so once you fix the parent the child needs a
  manual `retryDeadLetter` too. Declare `references` to avoid this. The same
  applies one level down: a grandchild table without references, under a child
  row that a dead parent holds, is sent and gets the same 422. A backing-off
  ancestor, by contrast, holds every descendant table.

### Data from before sign-in

The first account to sign in on a device that has never had one keeps the
existing local rows and uploads them (`claimUnownedData`, on by default).
Rows whose owner column names someone else are never uploaded and never
deleted: they stay on the device, counted in `status.unclaimed`. That count
comes from the store, so it survives restarts.

Pre-account guest rows (an anonymous session, say) are re-owned only when
their owner is in `guestIds(account)`, the explicit set of ids you know belong
to the account now signing in. It is a set rather than a predicate on purpose:
a store can hold a real user's rows (a migrated database, a restored backup),
and a blanket predicate would upload them under whoever signed in next. If you
learn a guest id later, call `claimGuestRows()`.

## Tests

Apps can test against the same fake: `import 'package:zonai_sync/testing.dart';`
for `FakeZonai`. It is test-only and deliberately not exported from the main
library.

```bash
dart test                                              # engine, with an in-memory zonai fake
ZONAI_E2E_BINARY=/path/to/zonai dart test --tags e2e   # against a real server (e2e/sync)
```
