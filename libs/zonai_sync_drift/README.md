# zonai_sync_drift

[drift](https://drift.simonbinder.eu) storage for [`zonai_sync`](../zonai_sync).

`DriftSyncStore` keeps sync bookkeeping in your app's own drift database: the
outbox, pull cursors, base revisions and the owning account. It lives in four
`_zonai_sync_*` tables created on `open`. Because they share the database with
your rows, a local edit and its outbox entry, or a pulled page and its cursor,
commit in one SQLite transaction.

You describe each synced table with a `DriftSyncTable`: read, write, delete
and clear by id in zonai's wire format. `zonai_sync_gen` generates these
from your server schema, or you can write them by hand:

```dart
final store = await DriftSyncStore.open(appDb, [CoursesSync(appDb), StudentsSync(appDb)]);
final sync = SyncEngine(remote: ZonaiSyncRemote(client), local: store, tables: [...], account: ...);
```
