---
title: Database
description: Using the Dart client to read, write, and stream database records.
---

The `db` property on `ZonaiClient` wraps the server's database endpoints. All
methods accept a body object that mirrors the corresponding REST request body.

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

## Real-Time Streaming

`client.db.listen` exposes three streaming methods that keep a `Stream` open
and push updates whenever the underlying data changes.

### Stream a single record

```dart
client.db.listen
    .one(body: StreamBody(table: 'posts', id: 'abc_ps'))
    .listen((record) {
  // Called whenever the record changes
});
```

### Stream a list

```dart
client.db.listen
    .list(body: StreamListBody(table: 'posts', limit: 20))
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
final sub = client.db.listen.list(...).listen((_) {});
// Later:
await sub.cancel();
```
