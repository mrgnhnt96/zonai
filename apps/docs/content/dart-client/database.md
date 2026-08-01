---
title: Database
description: Using the Dart client to read, write, and stream database records.
---

The `db` property on `ZonaiClient` wraps the server's database endpoints. All
methods accept a body object that mirrors the corresponding REST request body.

<Info>
**Start here for live UI:** [Real-Time Streaming](#real-time-streaming) below
(`client.db.listen`). Do not invent a poller. Server guide:
[Streaming (Live Queries)](/operations/streaming).
</Info>

## Real-Time Streaming

Zonai pushes live query updates over long-lived HTTP — you do **not** need to poll.
The framework names this **stream** / **listen** (not "realtime", "SSE", or
"WebSocket"). Server routes: `GET /db/stream`, `/db/stream/list`, `/db/stream/count`.
Full protocol notes: [Streaming (Live Queries)](/operations/streaming).

`client.db.listen` exposes three methods that keep a `Stream` open and emit whenever
the underlying SQLite result changes.

### Stream a single record

```dart
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

```dart
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

```dart
client.db.listen
    .count(body: StreamCountBody(table: 'posts'))
    .listen((total) {
      // Called whenever the count changes
    });
```

Cancel the subscription when you no longer need updates:

```dart
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

```dart
final record = await client.db.get(
  body: GetBody(table: 'posts', id: 'abc_ps'),
);
// record is Map<String, Object?>
```

### List records

```dart
final page = await client.db.list(
  body: ListBody(table: 'posts', limit: 20),
);
// page is Paginated<Map<String, Object?>>
```

### Count records

```dart
final total = await client.db.count(
  body: CountBody(table: 'posts'),
);
```

### Create a record

```dart
final created = await client.db.create(
  body: CreateBody(table: 'posts', data: {'title': 'Hello'}),
);
```

### Update records

```dart
// Update many records matching a filter
await client.db.update(
  body: UpdateBody(table: 'posts', data: {'published': true}, where: ...),
);

// Update exactly one record by ID
await client.db.updateOne(
  body: UpdateOneBody(table: 'posts', id: 'abc_ps', data: {'title': 'New title'}),
);
```

### Delete records

```dart
// Delete many records matching a filter
await client.db.delete(
  body: DeleteBody(table: 'posts', where: ...),
);

// Delete exactly one record by ID
await client.db.deleteOne(
  body: DeleteOneBody(table: 'posts', id: 'abc_ps'),
);
```
