---
title: Authentication
description: How the Dart client handles token acquisition and the X-Auth response header pattern.
---

The Dart client manages authentication tokens automatically. After the first
successful auth call, the access token is stored and injected into every
subsequent request without any additional code in the application.

## The X-Auth Header Pattern

Zonai uses a response-header mechanism to deliver access tokens to the client.
Every auth endpoint — sign-in, sign-up, OTP confirmation, magic-link
confirmation, and token refresh — sets an `X-Auth` header on the response in
addition to the JSON body:

```
HTTP/1.1 200 OK
X-Auth: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Content-Type: application/json

{ "data": { "accessToken": "eyJ...", "user": { ... } } }
```

The client's `Interceptor` reads `X-Auth` from every incoming response and
persists the value via the configured `ZonaiStorage`. On every outgoing request
the same interceptor reads the stored token and injects it as:

```
Authorization: Bearer <token>
```

This means the application never needs to extract the token from a response body
or attach it to a request manually.

## Token Lifecycle

```
1.  Client calls POST /auth/sign-in with credentials
2.  Server validates credentials
3.  Server sets X-Auth: <accessToken> on the response
4.  Interceptor reads X-Auth → stores token via ZonaiStorage
5.  All subsequent requests: Interceptor injects Authorization: Bearer <token>
6.  When POST /auth/refresh is called:
      Server revokes the old token
      Server sets X-Auth: <newAccessToken> on the response
      Interceptor replaces the stored token automatically
7.  On logout, the token is revoked server-side; clear local storage manually
    if needed (e.g., ZonaiStorage.none() or clearing the storage directory)
```

See [Session Management](/authentication/session-management) for token expiry
and refresh details on the server side.

## Setting a Token Manually

If you obtain a token outside of the client — for example from a native auth
SDK or a server-side session — you can seed it directly into the server's
storage before making requests:

```dart
import 'package:zonai_client/server.dart';
import 'package:zonai_client/zonai_client.dart';

final server = Server(
  storage: ZonaiStorage(directory: '/var/lib/myapp'),
);
await server.storage.save('token', '<your-access-token>');

final client = ZonaiClient.server(server: server);
```

## Unauthenticated Requests

If no token is stored and a request reaches the interceptor without an
`Authorization` header already present, the client throws a `StateError`. For
endpoints that are intentionally unauthenticated (e.g., a public health check),
use `ZonaiStorage.none()` so the interceptor skips token injection:

```dart
final server = Server(storage: ZonaiStorage.none());
final client = ZonaiClient.server(server: server);
await client.health(); // no Authorization header added
```
