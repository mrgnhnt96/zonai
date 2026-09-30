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
dropped.

## Server table requirements

Until `zonai_sync_schema` ships, declare these columns yourself:

- `updated_at`: `$.updatedAt(...)` with a **non-nullable** `DateTime` field, so
  zonai stamps it on insert as well as on update.
- `rev`: an `int` column. The client conditions every update on it.
- `deleted_at`: a nullable `DateTime`, the tombstone. Deny hard deletes in the
  row rules.
- An owner column (default `owner_id`). Row rules check it on `canView`,
  `canCreate`, and **both sides** of `canUpdate`.
- Table rules allow `canUpdate` for signed-in users, so the row rules decide.

`e2e/sync` in this repo is a complete, working example.

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
| offline, timeout | keeps the change queued without spending a retry attempt |
| 401 | pauses (`SyncPhase.needsAuth`) until `resume()` |
| 403, 400, 422 | dead-letters it: visible in `status.deadLetters`, with `retryDeadLetter`/`discardDeadLetter` |
| 409 on create | reconciles with the existing row |
| 412 / revision mismatch | applies the table's conflict policy |
| 429 | waits for `retryAfter` |
| 5xx | backs off exponentially, dead-letters after `RetryPolicy.maxAttempts` |

## Tests

```bash
dart test                                              # engine, with an in-memory zonai fake
ZONAI_E2E_BINARY=/path/to/zonai dart test --tags e2e   # against a real server (e2e/sync)
```
