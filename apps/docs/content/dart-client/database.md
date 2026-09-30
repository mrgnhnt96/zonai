---
title: Database
description: Using the Dart client to read, write, and stream database records.
---

The `db` property on `ZonaiClient` wraps the server's database endpoints. All
methods accept a body object that mirrors the corresponding REST request body.

<Info>

**Live UI:** see [Real-Time Streaming](#real-time-streaming) below
(`client.db.listen`). Server guide: [Streaming (Live Queries)](/operations/streaming).

</Info>

## Real-Time Streaming

Zonai pushes live query updates over long-lived HTTP. Server routes:
`GET /db/stream`, `/db/stream/list`, `/db/stream/count`.
Full protocol notes: [Streaming (Live Queries)](/operations/streaming).

`client.db.listen` exposes three methods that keep a `Stream` open and emit whenever
the underlying SQLite result changes.

### Stream a single record

```dart in:client
client.db.listen
    .one(
      body: StreamBody(
        table: 'posts',
        where: Eq('id', 'abc_ps'),
      ),
      fromJson: (row) => row,
    )
    .listen((record) {
      // Called on connect and whenever the record changes
    });
```

### Stream a list

```dart in:client
client.db.listen
    .list(
      body: StreamListBody(table: 'posts', limit: 20),
      fromJson: (row) => row,
    )
    .listen((records) {
      // Called whenever the result set changes
    });
```

### Stream a count

```dart in:client
client.db.listen
    .count(body: StreamCountBody(table: 'posts', where: Eq('published', true)))
    .listen((total) {
      // Called whenever the count changes
    });
```

Cancel the subscription when you no longer need updates:

```dart in:client
final sub = client.db.listen
    .list(
      body: StreamListBody(table: 'posts'),
      fromJson: (row) => row,
    )
    .listen((_) {});
// Later:
await sub.cancel();
```

## CRUD Operations

### Get a single record

```dart in:client
final record = await client.db.get(
  body: GetBody(table: 'posts', where: Eq('id', 'abc_ps')),
  fromJson: (row) => row,
);
// record is Map<String, Object?>
```

### List records

```dart in:client
final page = await client.db.list(
  body: ListBody(table: 'posts', limit: 20),
  fromJson: (row) => row,
);
// page is Paginated<Map<String, Object?>>
```

### Count records

```dart in:client
final total = await client.db.count(
  body: CountBody(table: 'posts'),
);
```

### Create a record

```dart in:client
final created = await client.db.create(
  body: CreateBody(table: 'posts', object: {'title': 'Hello'}),
  fromJson: (row) => row,
);
```

### Update records

```dart in:client
// Update every record matching a filter
await client.db.updateMany(
  body: UpdateBody(
    table: 'posts',
    updates: [Update.column('published', UpdateValue.literal(true))],
    where: Eq('author_id', 'abc_au'),
  ),
  fromJson: (row) => row,
);

// Update exactly one record
await client.db.update(
  body: UpdateOneBody(
    table: 'posts',
    updates: [Update.column('title', UpdateValue.literal('New title'))],
    where: Eq('id', 'abc_ps'),
  ),
  fromJson: (row) => row,
);
```

### Update only if the row is still what you read

`expect` is a precondition every target row must meet. If any row fails it, nothing is written and the update throws `PreconditionFailedException`, whose `current` carries the failing rows as they are now. That's optimistic concurrency: read a row, then write it back only if nobody else changed it in between.

```dart in:client
try {
  await client.db.update(
    body: UpdateOneBody(
      table: 'posts',
      where: Eq('id', 'abc_ps'),
      updates: [Update.column('title', UpdateValue.literal('New title'))],
      expect: Eq('rev', 3), // the revision you read
    ),
    fromJson: (row) => row,
  );
} on PreconditionFailedException catch (e) {
  final now = e.current.single; // someone else's edit; reconcile with it
  print('changed under us: $now');
}
```

- A precondition failure is a `412`, with `error.code` set to `precondition_failed` and the rows in `error.details.current`. It is not a `404`: a row that no longer matches `where` at all still returns `404` from `update`, or an empty list from `updateMany`. The two mean different things to a client that is reconciling.
- `updateMany` is refused whole when any target fails, and `current` lists only the failing rows.
- `current` holds only rows you may view.
- On the wire, `expect` must be a where-object. Missing or `null` means no precondition; anything else (`[]`, `"rev=3"`) is a `400` with code `invalid_expect`, never an unconditional write. An object that isn't a valid where (`{}`, or an unknown `type`) is a `400` with code `invalid_body`, the same answer as any other malformed request body.
- Every permission refusal comes first: a `403` always wins over a `412`, and a `beforeUpdate` hook never runs for an update the precondition refuses.
- A server older than this feature ignores `expect` and applies the update unconditionally. Know your server version before you rely on it.

### Delete records

```dart in:client
// Delete every record matching a filter
await client.db.deleteMany(
  body: DeleteBody(table: 'posts', where: Eq('author_id', 'abc_au')),
);

// Delete exactly one record
await client.db.delete(
  body: DeleteOneBody(table: 'posts', where: Eq('id', 'abc_ps')),
);
```
