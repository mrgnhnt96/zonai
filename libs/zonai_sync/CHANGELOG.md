## 0.1.0-dev.1

- First cut: `SyncEngine` (transactional outbox, scoped keyset pulls,
  revision-based conflict policies, dead letters, account-scoped state),
  `ZonaiSyncRemote` for today's `/db` API, and `MemorySyncStore`.
- Fourth review: re-checks the live account after every store read, just
  before a request leaves (discard included). Replaces the `reownGuest`
  predicate with `guestIds(account)` and adds `claimGuestRows()`. A held row
  now holds child tables that declare no references. `status.unclaimed` is
  counted from the store after the claim commits, and an account-change abort
  no longer leaves the status on `pushing`.
- `package:zonai_sync/testing.dart` exports `FakeZonai` for app tests. It is test-only and not exported from the main library.
