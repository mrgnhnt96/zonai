---
title: Auth Hooks
description: beforeSignUp, onSignUp, onSignIn, onRefresh, onLogout, and the other auth extension hooks.
---

Auth hooks fire at key points in the authentication lifecycle. They are available by mixing `AuthExtension` into the extension class for an auth table. `AuthExtension` takes the same row type you gave `Extension`.

## Enabling Auth Hooks

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

class UserExtensions extends Extension<User> with AuthExtension<User> {
  UserExtensions() : super(users);

  @override
  Future<void> onSignUp(User user, Jwt? jwt) async {
    // ...
  }

  @override
  Future<void> onSignIn(User user, Jwt? jwt) async {
    // ...
  }
}

UserExtensions main() => UserExtensions();
```

| Hook | When it fires | Default |
| ---- | ------------- | ------- |
| `beforeSignUp(SignUpCandidate candidate, Jwt? jwt)` | Before a new account row is inserted. Throw to decline | nothing |
| `onSignUp(T user, Jwt? jwt)` | After a new account is created and its session issued | sends the verify-email link |
| `onSignIn(T user, Jwt? jwt)` | After an existing account signs in | calls `loginNotice` (not implemented yet; see below) |
| `onRefresh(T user, Jwt? jwt)` | After `POST /auth/refresh` issues a new token | nothing |
| `onLogout(T user, Jwt? jwt)` | After `DELETE /auth` revokes the current session | nothing |
| `onPasswordReset(T user, Jwt? jwt)` | After a password-reset email has been sent | nothing |
| `onExternalAuthFirstSeen(Map<String, Object?> claims)` | An external IdP or OAuth identity has no row yet | nothing |

The defaults only apply when the table has an email column. Overriding `onSignUp` or `onSignIn` replaces its default email; call `super.onSignUp(user, jwt)` from your override to keep the verify-email link.

The server does not implement the built-in `loginNotice` email yet, so the default `onSignIn` sends nothing and the server logs an error on each sign-in. Override `onSignIn` to stop that, and send your own notice with a [custom template](/extensions/side-effects-email#sending-custom-emails) if you want one.

**What `jwt` holds.** In `onSignUp`, `onSignIn` and `onRefresh` it is the **new** session just minted for `user`, so `get` and `mutate` in those hooks act as that user. In `onLogout` it is the session being revoked. In `beforeSignUp` it is the caller's token, usually `null`.

Sign-ups do **not** fire the [create hooks](/extensions/create-hooks). `beforeCreate` and `afterCreateSuccess` on an auth table run only for rows created through `/db` or `mutate.create`.

## beforeSignUp(SignUpCandidate candidate, Jwt? jwt)

Runs before the account row is inserted. It is the one auth hook that can change the outcome.

### Declining a sign-up

Throw `SignUpDeclinedException` and the caller is answered **403** with the reason you chose:

```dart in:extension-user
@override
Future<void> beforeSignUp(SignUpCandidate candidate, Jwt? jwt) async {
  if (!candidate.email.endsWith('@acme.com')) {
    throw const SignUpDeclinedException('Sign-up is limited to Acme staff');
  }
}
```

```json
{ "error": "Sign-up is limited to Acme staff" }
```

The reason reaches the caller **verbatim**, unlike the generic `Forbidden` most 403s carry, so put nothing in it they should not see. Nothing is left behind: no row, no session, and no verification email. Any other exception aborts the sign-up too, but as a `500`.

### What the candidate holds

`candidate` is the sign-up **request**, not your row class, because there is no row yet:

| Field    | What it is                                                  |
| -------- | ----------------------------------------------------------- |
| `email`  | The address the sign-up was made with                       |
| `object` | The extra columns the body carried, as the client sent them |
| `table`  | The auth table being signed up into                         |

`candidate['nickname']` is shorthand for `candidate.object['nickname']`. Nothing in `object` has been through rules or the insert yet, so it is not necessarily what the row will end up holding. The address is not duplicated into `object`.

### Which flows run it

It runs on the three flows that insert an auth row directly: **password**, **OTP** and **magic-link** sign-up.

For OTP and magic link, the account is created when the code or link is **verified**, not when it is requested. The hook runs at both points: once when the code is requested, before any email is sent, and again at verification, just before the insert. A hook with side effects must tolerate running twice for one sign-up. The password flow requests and inserts in one call, so it runs once there.

It does **not** run for a first-seen OAuth or external-IdP identity. Those are provisioned by `onExternalAuthFirstSeen`, which declines by returning without inserting a row. That path answers `401`, not 403. See [External Identity Providers](/authentication/external-idp#provisioning-users).

## onSignUp(T user, Jwt? jwt)

Fires after the sign-up INSERT commits and the new account's session has been issued. By default it sends the verify-email link.

```dart in:extension-user
@override
Future<void> onSignUp(User user, Jwt? jwt) async {
  email.send.verifyEmail(
    EmailAddress(address: user.email),
    table: 'users',
  );

  // Create a companion row (e.g. a billing profile)
  mutate.create.one(
    tableName: 'profiles',
    object: {'user_id': user.id.value},
  );
}
```

## onSignIn(T user, Jwt? jwt)

Fires after credentials are validated and the new session is created, before the token is returned. Throwing here fails the request, so the client never receives the token. By default it calls the built-in `loginNotice` email, which is not implemented yet (see above).

```dart in:extension-user
@override
Future<void> onSignIn(User user, Jwt? jwt) async {
  mutate.update.one(
    table: 'users',
    updates: [Update.column('last_signed_in_at', UpdateValue.literal(DateTime.now()))],
    where: Eq('id', user.id.value),
  );
}
```

Use for: recording last-login timestamp, sending login-notification emails, triggering security alerts.

## onRefresh(T user, Jwt? jwt)

Fires when the client exchanges an existing token for a new one via `POST /auth/refresh`. The old token is revoked. No email is sent by default.

```dart in:extension-user
@override
Future<void> onRefresh(User user, Jwt? jwt) async {
  // Update last active timestamp
}
```

## onLogout(T user, Jwt? jwt)

Fires when the current session token is revoked via `DELETE /auth`. It does not fire when the token had already been revoked.

`DELETE /auth/all` ("log out everywhere") does **not** fire `onLogout`, and neither do the session revocations that follow a password reset or an admin removal. Do not rely on `onLogout` as the only place that cleans up after a user's sessions.

```dart in:extension-user
@override
Future<void> onLogout(User user, Jwt? jwt) async {
  // Revoke any push notification subscriptions for this user
}
```

## onPasswordReset(T user, Jwt? jwt)

Fires after `POST /auth/reset-password` has sent the reset link, and only when an account exists for the address. The email has already gone out before the hook runs, so there is no default email.

## onExternalAuthFirstSeen(Map<String, Object?> claims)

Called when a verified OAuth or external-IdP identity has no row in this table. Insert the row with `mutate.create.one` and the sign-in continues with it. See [External Identity Providers](/authentication/external-idp#provisioning-users).
