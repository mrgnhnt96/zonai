---
title: Storage
description: ZonaiStorage variants — file-backed, in-memory, and no-op — and when to use each.
---

`ZonaiStorage` is the persistence layer for the Dart client's access token.
It implements the `revali_client.Storage` interface and is passed to the
underlying `Server` on construction.

Three factory variants cover the common use cases:

## File-Backed Storage

```dart
ZonaiStorage(directory: '/var/lib/myapp')
```

Reads and writes a `zonai_storage.json` file inside `directory`. The token
survives process restarts, making this the right choice for:

- CLI tools that authenticate once and reuse the token across invocations
- Long-running background services
- Desktop or mobile applications where the platform provides a stable data directory

The directory must already exist; the client will not create it automatically.

## In-Memory Storage

```dart
ZonaiStorage.memory()
```

Holds values in a `Map` for the lifetime of the process. No files are read or
written. This is the default used by `ZonaiClient.instance` and by the
`ZonaiClient(...)` factory when no `storageDirectory` is provided.

Use in-memory storage when:

- The application authenticates on every launch anyway
- You are writing tests that must not share state between runs
- You want to avoid any filesystem dependency

## No-Op Storage

```dart
ZonaiStorage.none()
```

All reads return `null` and all writes are discarded. The token is never
stored or retrieved.

Use the no-op variant when:

- Requests are intentionally unauthenticated
- Token management is handled entirely by the caller (e.g., injecting the
  `Authorization` header directly)
- You want to assert in tests that no storage calls happen

<Info>
In debug builds, `ZonaiStorage.none()` triggers assertion failures if any
storage operation is attempted, making it easy to catch unexpected token
reads or writes during development.
</Info>

## Passing a Custom Storage

`ZonaiStorage` implements `revali_client.Storage`. You can pass your own
`Storage` implementation to `Server` if the built-in variants do not fit
your needs (e.g., an encrypted keychain, a platform-specific secure store,
or a test double):

```dart
import 'package:zonai_client/server.dart';
import 'package:zonai_client/zonai_client.dart';

final server = Server(storage: MyCustomStorage());
final client = ZonaiClient.server(server: server);
```
