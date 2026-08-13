---
title: Storage
description: ZonaiStorage variants — file-backed, in-memory, and no-op — and when to use each.
---

`ZonaiStorage` provides the persistence used for the Dart client's access
token. Its variants implement the `revali_client.Storage` interface and are
passed to the underlying `Server` on construction.

Three variants cover the common use cases. The file-backed one lives in
`package:zonai_client/storage.dart` rather than the main library, so a browser
build does not pull `package:file` into its graph:

## File-Backed Storage

```dart in:client-expression
ZonaiFileStorage(directory: '/var/lib/myapp')
```

It comes from `package:zonai_client/storage.dart` rather than the main
library. The browser-safe variants below need no extra import:

```dart in:client-expression
ZonaiStorage.memory() // browser-safe; file storage needs the other import
```

Reads and writes a `zonai_storage.json` file inside `directory`. The token
survives process restarts, making this the right choice for:

- CLI tools that authenticate once and reuse the token across invocations
- Long-running background services
- Desktop or mobile applications where the platform provides a stable data directory

The directory must already exist; the client will not create it automatically.

## In-Memory Storage

```dart in:client-expression
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

```dart in:client-expression
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

Each variant implements `revali_client.Storage`. You can pass your own
`Storage` implementation to `Server` if the built-in variants do not fit
your needs (e.g., an encrypted keychain, a platform-specific secure store,
or a test double). `Server` comes from `package:zonai_client/server.dart`:

```dart in:client-custom-storage
final server = Server(storage: MyCustomStorage());
final client = ZonaiClient.server(server: server);
```
