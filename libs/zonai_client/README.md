# zonai_client

Generated HTTP client for the Zonai Revali server. Provides a typed Dart API over the server's REST endpoints, with built-in token management via the `X-Auth` response header pattern.

## Installation

This package is not published to pub.dev. Add it as a path dependency in your `pubspec.yaml`:

```yaml
dependencies:
  zonai_client:
    path: ../zonai_client   # adjust path as needed
```

## Quick Start

```dart
import 'package:zonai_client/zonai_client.dart';

// Use the singleton (memory storage, default base URL)
final client = ZonaiClient.instance;

// Or configure explicitly
final client = ZonaiClient(
  baseUrl: 'https://api.example.com',
  storageDirectory: '/path/to/storage',
);

// Check server health
final healthy = await client.health();
```

The base URL defaults to `http://localhost:8080`. You can override it via the
`baseUrl` constructor parameter or the `BASE_URL` compile-time environment
variable:

```sh
dart run --define=BASE_URL=https://api.example.com
```

## Authentication & X-Auth Header

Zonai uses a **response-header token pattern** to distribute access tokens
without requiring the client to parse response bodies.

### How it works

1. The client calls an auth endpoint (sign-in, sign-up, OTP confirmation, etc.)
2. The server validates the request and sets `X-Auth: <accessToken>` on the
   response, alongside the JSON body.
3. The `Interceptor` reads `X-Auth` from every response and persists the token
   via the configured `ZonaiStorage`.
4. On all subsequent requests, `Interceptor` automatically injects
   `Authorization: Bearer <token>` before the request is sent.
5. On token refresh, the server revokes the old token and issues a new one —
   the new token arrives in `X-Auth` and replaces the stored value automatically.

No manual token management is required. Once the user authenticates, all
subsequent calls are authenticated transparently.

### Setting a token manually

If you already have a token (e.g., from a native auth flow), set it directly on
the `Server`'s storage before making requests:

```dart
final server = Server(
  storage: ZonaiStorage(directory: '/path/to/storage'),
);
await server.storage.save('token', '<your-access-token>');

final client = ZonaiClient.server(server: server);
```

## Storage

Storage controls where the access token is persisted between requests.

| Constructor | Behavior |
|---|---|
| `ZonaiStorage(directory: '/path')` | File-backed; persists to `zonai_storage.json` in the given directory |
| `ZonaiStorage.memory()` | In-memory only; token is lost when the process exits |
| `ZonaiStorage.none()` | No-op; token is never stored or retrieved |

```dart
// File-backed (recommended for CLIs and server-side tools)
final client = ZonaiClient(storageDirectory: '/var/lib/myapp');

// Memory (default for ZonaiClient.instance; suitable for short-lived processes)
final client = ZonaiClient();

// No-op (useful when you manage tokens yourself)
final server = Server(storage: ZonaiStorage.none());
final client = ZonaiClient.server(server: server);
```

## Services

### `client.db` — Database

CRUD and real-time streaming over Zonai's database endpoints.

```dart
// Create a record
final record = await client.db.create(body: CreateBody(...));

// List records
final page = await client.db.list(body: ListBody(...));

// Stream live updates
client.db.listen.list(body: StreamListBody(...)).listen((records) {
  print(records);
});
```

Available methods: `get`, `list`, `count`, `create`, `createMany`, `update`, `updateMany`,
`delete`, `deleteMany`, and streaming variants via `client.db.listen`.

### `client.photos` — Photos

Upload, retrieve, and delete photos as byte streams.

```dart
// Upload
final result = await client.photos.create(
  image: File('photo.jpg').openRead(),
  meta: PhotoCreateMeta(...),
);

// Download
final bytes = client.photos.get(id: result['id'] as String);
await for (final chunk in bytes) { ... }

// Delete
await client.photos.delete(id: '<id>');
```

### `client.email` — Email

Send transactional emails.

```dart
await client.email.sendOtp(email: SendOtpEmail(...));
await client.email.sendMagicLink(email: SendMagicLinkEmail(...));
await client.email.sendVerifyEmail(email: SendVerifyEmailEmail(...));
await client.email.sendPasswordReset(email: SendResetPasswordEmail(...));
```

## Advanced: Direct Server Instantiation

For full control over the HTTP client and storage, construct a `Server` directly
and pass it to `ZonaiClient.server`:

```dart
import 'package:zonai_client/server.dart';
import 'package:zonai_client/zonai_client.dart';

final server = Server(
  baseUrl: Uri.parse('https://api.example.com'),
  storage: ZonaiStorage(directory: '/var/lib/myapp'),
);

final client = ZonaiClient.server(server: server);
```
