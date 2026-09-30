## 0.1.0-dev.1

- First cut: `SyncEngine` (transactional outbox, scoped keyset pulls,
  revision-based conflict policies, dead letters, account-scoped state),
  `ZonaiSyncRemote` for today's `/db` API, and `MemorySyncStore`.
- Fourth review: re-checks the live account after every store read, just
  before a request leaves (discard included). Replaces the `reownGuest`
  predicate with `guestIds(account)` and adds `claimGuestRows()`. `status.unclaimed` is
  counted from the store after the claim commits, and an account-change abort
  no longer leaves the status on `pushing`.
- `package:zonai_sync/testing.dart` exports `FakeZonai` for app tests. It is test-only and not exported from the main library.
- Fifth review: a claim never re-owns a row that has synced (it has a base revision), and `claimGuestRows()` counts inside its transaction. Reverted the fourth review's table block for held rows: a dead parent froze unrelated grandchildren, and a waiting one was already covered by the ancestor walk.
- `orderTables` rejects a reference to a table that isn't a parent (a self-reference, such as folders or threads, is allowed). With partial references, parents that no reference covers still hold the table.
- Morgan's review of #48:
  - every request times out after `requestTimeout` and counts as offline;
  - the library no longer imports `dart:io`, so it builds for the web;
  - `ZonaiSyncCapabilities.serverRevisionTables` enables server revision per table;
  - offline passes retry after `offlineRetry`, and backoffs and 429s retry when their delay ends;
  - a rate-limited pass no longer leaves the status on `pushing`;
  - the README covers JSON-only values, writes that bypass sync, the revision migration order and `needsAuth`.
