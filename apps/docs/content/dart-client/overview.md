---
title: Overview
description: The generated Dart client for the Zonai server — installation, quick start, and configuration.
---

`zonai_client` is a generated Dart package that wraps the Zonai server's REST API.
It handles token storage, automatic header injection, and response parsing so that
application code can call typed methods instead of managing HTTP requests directly.

Prefer this package over a hand-written `http` client. It covers **auth**, **admin
auth**, **db** (CRUD + **live streams** via `client.db.listen`), **photos**, and
**email**.

<Info>

For live screens, use `client.db.listen.one|list|count`. Full guide:
[Streaming (Live Queries)](/operations/streaming).

</Info>

<Info>

**There is a typed layer on top of this one.** `client.db` takes a table name as a
string and hands back a `Map` you decode yourself. [`zonai gen client`](/cli/gen)
generates per-table APIs from your schema — `client.posts.list(...)` returning
`PostsRow` — as an *extension* on the client described here, so both styles work in
one file. See [Typed Client](/dart-client/typed-client).

This page covers installing `zonai_client` and pointing it at a server, which the
typed client needs first either way.

</Info>

## Installation

```yaml
dependencies:
  zonai_client: # latest version
```

## Quick Start

```dart
import 'package:zonai_client/zonai_client.dart';

Future<void> main() async {
  // Singleton — memory storage, base URL from BASE_URL env var or
  // http://localhost:8080
  final client = ZonaiClient.instance;

  // Check that the server is reachable
  final healthy = await client.health();

  // Query the database. The table is a string and the row arrives as a Map;
  // `zonai gen client` generates `client.posts.list()` returning a typed row
  // instead — see /dart-client/typed-client.
  final page = await client.db.list(
    body: ListBody(table: 'posts'),
    fromJson: (row) => row,
  );
}
```

## Configuration

`ZonaiClient` accepts two optional parameters:

| Parameter          | Default                                       | Description     |
| ------------------ | --------------------------------------------- | --------------- |
| `baseUrl`          | `BASE_URL` env var or `http://localhost:8080` | Server base URL |
| `storageDirectory` | _(none — memory storage)_                     |

```dart in:client
final client = ZonaiClient(
  baseUrl: Uri.parse('https://api.example.com'),
  storageDirectory: '/var/lib/myapp',
);
```

The `BASE_URL` compile-time environment variable is read when no `baseUrl` is passed:

```sh
dart run --define=BASE_URL=https://api.example.com lib/main.dart
```

This `--define` flag belongs to `dart run`/`dart compile` and only affects how *this client script* reads `BASE_URL` — it's unrelated to the Zonai server's own env handling. To set `BASE_URL` for the server itself, see [Environment Variables](/configuration/environment-variables).

## Singleton vs. Explicit Instance

`ZonaiClient.instance` is a lazy singleton backed by in-memory storage. It is
convenient for applications that authenticate on every launch and do not need to
persist tokens across restarts.

For long-lived processes — CLI tools, background services — use an explicit
instance with file-backed storage so the token survives restarts:

```dart
import 'dart:io';

import 'package:zonai_client/zonai_client.dart';

void main() {
  final client = ZonaiClient(
    storageDirectory: '${Platform.environment['HOME']}/.myapp',
  );
}
```

## Direct Server Instantiation

For full control over the HTTP client and storage, construct a `Server` directly
and pass it to `ZonaiClient.server`. Import `server.dart` to access the `Server`
class:

```dart
import 'package:zonai_client/server.dart';
import 'package:zonai_client/storage.dart';
import 'package:zonai_client/zonai_client.dart';

void main() {
  final server = Server(
    baseUrl: Uri.parse('https://api.example.com'),
    storage: ZonaiFileStorage(directory: '/var/lib/myapp'),
  );

  final client = ZonaiClient.server(server: server);
}
```

This is also the pattern to use in tests — pass a `ZonaiStorage.memory()` to
keep storage isolated between test cases.
