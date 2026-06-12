---
title: Overview
description: The generated Dart client for the Zonai server — installation, quick start, and configuration.
---

`zonai_client` is a generated Dart package that wraps the Zonai server's REST API.
It handles token storage, automatic header injection, and response parsing so that
application code can call typed methods instead of managing HTTP requests directly.

## Installation

```yaml
dependencies:
  zonai_client: # latest version
```

## Quick Start

```dart
import 'package:zonai_client/zonai_client.dart';

// Singleton — memory storage, base URL from BASE_URL env var or http://localhost:8080
final client = ZonaiClient.instance;

// Check that the server is reachable
final healthy = await client.health();

// Query the database
final page = await client.db.list(body: ListBody(table: 'posts'));
```

## Configuration

`ZonaiClient` accepts two optional parameters:

| Parameter          | Default                                       | Description     |
| ------------------ | --------------------------------------------- | --------------- |
| `baseUrl`          | `BASE_URL` env var or `http://localhost:8080` | Server base URL |
| `storageDirectory` | _(none — memory storage)_                     |

```dart
final client = ZonaiClient(
  baseUrl: 'https://api.example.com',
  storageDirectory: '/var/lib/myapp',
);
```

The `BASE_URL` compile-time environment variable is read when no `baseUrl` is passed:

```sh
dart run --define=BASE_URL=https://api.example.com lib/main.dart
```

## Singleton vs. Explicit Instance

`ZonaiClient.instance` is a lazy singleton backed by in-memory storage. It is
convenient for applications that authenticate on every launch and do not need to
persist tokens across restarts.

For long-lived processes — CLI tools, background services — use an explicit
instance with file-backed storage so the token survives restarts:

```dart
final client = ZonaiClient(
  storageDirectory: Platform.environment['HOME']! + '/.myapp',
);
```

## Direct Server Instantiation

For full control over the HTTP client and storage, construct a `Server` directly
and pass it to `ZonaiClient.server`. Import `server.dart` to access the `Server`
class:

```dart
import 'package:zonai_client/server.dart';
import 'package:zonai_client/zonai_client.dart';

final server = Server(
  baseUrl: Uri.parse('https://api.example.com'),
  storage: ZonaiStorage(directory: '/var/lib/myapp'),
);

final client = ZonaiClient.server(server: server);
```

This is also the pattern to use in tests — pass a `ZonaiStorage.memory()` to
keep storage isolated between test cases.
