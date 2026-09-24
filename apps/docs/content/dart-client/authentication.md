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
7.  client.auth.logout() revokes the token server-side but leaves it in
    storage; call client.auth.clearToken() as well
```

See [Session Management](/authentication/session-management) for token expiry
and refresh details on the server side.

## Forced Password Reset

When an account owes a new password, a correct password sign-in does not
fail with bad credentials — it throws `PasswordResetRequiredException`,
carrying a one-time ticket (see [Forced Password
Reset](/authentication/password-auth#forced-password-reset)).
`completePasswordReset` redeems the ticket with the password the user just
chose, then signs in again with it:

```dart in:client
const email = 'alice@example.com';
try {
  await client.auth.signIn(
    body: SignInAuthBody(table: 'users', email: email, password: 'hunter2'),
  );
} on PasswordResetRequiredException catch (e) {
  // e.reason: adminForced, compromised, temporaryPassword or passwordPolicy.
  // e.expiresIn: how long the ticket is good for (15 minutes).
  // Ask the user for a new password here, explaining why with e.reason.
  const newPassword = 'their-new-password';
  await client.auth.completePasswordReset(
    refusal: e,
    email: email,
    newPassword: newPassword,
  );
}
```

If the new password equals the old one, `completePasswordReset` throws the
server's `422` unchanged — and the ticket is **not** used up, so pass the same
exception again with a different password. `client.auth.admin.signIn` and
`client.auth.admin.completePasswordReset` do the same for admin accounts.

`PasswordResetRequiredException.toString()` deliberately omits the ticket, so
it is safe to log.

## Setting a Token Manually

If you obtain a token outside of the client — for example from a native auth
SDK, a server-side session, or an [API token](/authentication/api-tokens) minted
with `zonai db token create` — you can seed it directly into the server's
storage before making requests:

```dart
import 'package:zonai_client/server.dart';
import 'package:zonai_client/storage.dart';
import 'package:zonai_client/zonai_client.dart';

Future<void> main() async {
  final server = Server(
    storage: ZonaiFileStorage(directory: '/var/lib/myapp'),
  );
  await server.storage.save('token', '<your-access-token>');

  final client = ZonaiClient.server(server: server);
}
```

## Unauthenticated Requests

If no token is stored and a request reaches the interceptor without an
`Authorization` header already present, the interceptor skips token injection
and sends the request without authentication. This allows the same client
instance to call both public endpoints (send OTP, health check) and authenticated
endpoints after sign-in.

To disable token storage entirely (e.g. for tests), use `ZonaiStorage.none()`:

```dart
import 'package:zonai_client/server.dart';
import 'package:zonai_client/zonai_client.dart';

Future<void> main() async {
  final server = Server(storage: ZonaiStorage.none());
  final client = ZonaiClient.server(server: server);
  await client.health(); // no Authorization header added
}
```
