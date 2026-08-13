---
title: Streaming (Live Queries)
description: Long-lived HTTP streams that push row, list, and count updates when SQLite data changes.
---

Zonai has **built-in live queries**. The server holds the HTTP connection open and pushes a new payload whenever the query's results change, so a client subscribes once instead of re-requesting on a timer.

Every table gets three streaming endpoints next to ordinary get / list / count. Prefer the generated Dart client (`zonai_client`) — `client.db.listen` — over hand-rolled HTTP.

## Endpoints

| Operation      | Method | Path              | Body location  | Rules / rate-limit bucket |
| -------------- | ------ | ----------------- | -------------- | ------------------------- |
| `stream-one`   | `GET`  | `/db/stream`      | `?body=<JSON>` | `canView` / `getPolicy`   |
| `stream-list`  | `GET`  | `/db/stream/list` | `?body=<JSON>` | `canList` / `limitPolicy` |
| `stream-count` | `GET`  | `/db/stream/count`| `?body=<JSON>` | `canCount` / `countPolicy`|

Payload types live in `zonai_schema`: `StreamBody`, `StreamListBody`, `StreamCountBody`.

Same conventions as other DB routes: **table name in the JSON body**, never in the path. Streams use the same authorization as their non-streaming counterparts.

## What "live" means

The server keeps the HTTP response open and **pushes a new JSON payload whenever the underlying SQLite query result changes** (inserts, updates, deletes that affect the query). Cancel the client subscription (or close the connection) when you are done.

## Prefer `zonai_client`

```dart
import 'package:zonai_client/zonai_client.dart';
import 'package:zonai_schema/zonai_schema.dart';

Future<void> main() async {
  final client = ZonaiClient.instance;

  // One row — where is required (usually id equality).
  final sub = client.db.listen
      .one(
        body: StreamBody(
          table: 'tasks',
          where: Eq('id', 'tk_abc123'),
        ),
        fromJson: (row) => row,
      )
      .listen((row) {
        // Fired on connect and whenever that row changes.
      });

  // Matching list
  client.db.listen
      .list(
        body: StreamListBody(
          table: 'tasks',
          where: Eq('isComplete', false),
          limit: 50,
        ),
        fromJson: (row) => row,
      )
      .listen((rows) { /* ... */ });

  // Count
  client.db.listen
      .count(body: StreamCountBody(table: 'tasks', where: Eq('isComplete', false)))
      .listen((total) { /* ... */ });

  await sub.cancel();
}
```

See [Dart Client — Database](/dart-client/database#real-time-streaming) for the full client API.

## Raw HTTP

Same `?body=` pattern as `GET /db` / `/db/list` / `/db/count`:

```
GET /db/stream?body={"table":"tasks","where":{"id":{"eq":"tk_abc123"}},"expand":[]}
GET /db/stream/list?body={"table":"tasks","where":{"isComplete":{"eq":false}},"limit":20}
GET /db/stream/count?body={"table":"tasks"}
```

Include `Authorization: Bearer <jwt>` when rules require it. Keep the connection open and read successive JSON events until you cancel.

## Rules and rate limits

There are no separate `canStream*` rule methods. Streaming reuses:

- `canView` → `/db/stream`
- `canList` → `/db/stream/list`
- `canCount` → `/db/stream/count`

Rate limits reuse `getPolicy`, `limitPolicy`, and `countPolicy` respectively.

## When streaming is not an option

Some constrained proxies will not hold a long-lived HTTP connection. Where that is the case, fall back to calling the ordinary `get` / `list` / `count` routes on a timer.
