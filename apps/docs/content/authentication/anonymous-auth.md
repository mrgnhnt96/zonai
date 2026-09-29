---
title: Anonymous Auth
description: Accounts that exist before their owner gives an address, upgraded in place.
---

Anonymous auth lets people use your app before they create an account. The first launch gets a real account and a real user id. Everything written from then on is owned by that id. When the person later proves an email address, that **same** account becomes a verified one. Nothing is re-keyed, so everything it owned is still its own.

An anonymous account is an ordinary row of your auth table whose email is `NULL`. It is not a separate kind of user, and rules, operations and extensions see it the way they see any other row.

## Enabling Anonymous Auth

Add `with AnonymousAuth` to an auth table, and make its email column nullable with `NullableEmailColumn`. Combine it with the method your users will upgrade through. Today that is an emailed code, so `OtpAuth` is the natural partner:

```dart no-analyze
final class UserTable extends AuthTable<User>
    with OtpAuth, AnonymousAuth {
  UserTable(super.$)
    : id = $.id('id', (s) => s.id, fromString: UsersId.new, generate: UsersId.generate),
      email = $.email<String?>('email', (s) => s.email),
      isVerified = $.isVerified('is_verified', (s) => s.isVerified);

  @override
  final IdColumn<UsersId> id;
  @override
  final NullableEmailColumn email; // NULL while the account is anonymous
  @override
  final IsVerifiedColumn isVerified;
}
```

Two declarations are refused when the server starts:

- **`AnonymousAuth` with a non-nullable email column.** An anonymous row has no address to store.
- **`AnonymousAuth` together with `AsAdmin`.** Admin is a property of the table, so every anonymous visitor would be an admin. Keep admins in a separate table.

A nullable email column is also refused on any table that does **not** mix in `AnonymousAuth`. `NULL` there means exactly one thing: this row is an anonymous account.

## The Flow

**Create an anonymous account:**

```
POST /auth/anonymous
```

```json
{ "table": "users", "object": { "display_name": "Guest" } }
```

The response is a normal session (`accessToken`, `user`, and the `X-Auth` header) plus one more field:

```json
{
  "accessToken": "…",
  "user": { "id": "…", "email": null, "is_verified": false, "display_name": "Guest" },
  "anonymousCredential": "zonai_anon_…"
}
```

`object` sets your own columns on the new row, as a sign-up body does. It can never set the address or the verification flag. A caller who is already signed in gets `409`.

<Warning>

`anonymousCredential` is returned **once**. It is the only way back into the account after the session expires, because an anonymous account has no address and no password to recover with. Keep it in the platform's secure storage: Keychain, Android Keystore, or whatever your platform provides. Losing it loses the account.

</Warning>

**Resume after the session expires:**

```
POST /auth/anonymous/resume
```

```json
{ "credential": "zonai_anon_…" }
```

This returns a fresh session for the same account. The credential is accepted here and nowhere else: it is never a bearer token. Once the account has been upgraded or deleted, it answers `401`.

**Upgrade to a verified account.** First, send a code to the address, carrying the anonymous session:

```
POST /auth/upgrade
Authorization: Bearer <anonymous session>
```

```json
{ "email": "ada@example.com" }
```

It always answers `200`, whether or not the address already has an account. That way an anonymous session can't be used to test which addresses exist.

Then prove the code with the **same** session:

```
POST /auth/upgrade/confirm
Authorization: Bearer <anonymous session>
```

```json
{ "email": "ada@example.com", "code": "123456", "password": "optional" }
```

On success the account keeps its id, gains the address (stored lowercased) and becomes verified. The response is a new session. Everything that proved "anonymous" is retired together: every earlier session and the device credential. `password` is optional; on a table that takes one, it is set in the same write, after the address is proven.

A code only works for the session that requested it. The same six digits from any other session count as a wrong code.

If the address already belongs to another account in the table, confirm answers `409` with the structured error `{"error": {"code": "email_in_use", …}}`. The anonymous account is left exactly as it was. Zonai never merges two accounts on anyone's behalf; the usual recovery is to sign in to the existing account instead.

## From the Dart Client

```dart no-analyze
final created = await client.auth.signInAnonymously(table: 'users');
await secureStorage.write('anonymous_credential', created.credential);

// Later, after the session has expired:
await client.auth.resumeAnonymous(
  credential: (await secureStorage.read('anonymous_credential'))!,
);

// When the person is ready to keep their account:
await client.auth.requestUpgrade(email: 'ada@example.com');
try {
  await client.auth.confirmUpgrade(email: 'ada@example.com', code: code);
  await secureStorage.delete('anonymous_credential'); // retired by the server
} on EmailInUseException {
  // Offer "sign in to your existing account" instead.
}
```

The client stores the session the way it stores every session. It deliberately does **not** store the credential, because the token storage you give the client is often not secure storage.

## Rules and Hooks

`jwt.isAnonymous` tells a rule whether the caller is still anonymous:

```dart no-analyze
@override
Future<bool> canCreate(Jwt? jwt, Order row) async =>
    jwt != null && !jwt.isAnonymous;
```

The server re-derives `isAnonymous` from the session record on every request, the same way it re-derives admin status, so a token that claims otherwise is not believed. It cannot go stale: upgrading revokes every session the account held.

- **Refusing anonymous accounts** is `AuthRowRules.canSignUp(jwt, AuthType.anonymous)`. It defaults to `true` on an `AnonymousAuth` table (and to `false` on an `AsAdmin` one, as for every method). Resuming is `canSignIn(jwt, AuthType.anonymous)`.
- **An owner cannot change their own address or verification flag** on an `AnonymousAuth` table. The default `AuthRowRules.canUpdate` refuses it; only the upgrade flow writes them, after proof. If you override `canUpdate`, keep that property.
- **`onSignUp`** runs when the anonymous account is created. The default sends no verify email, because there is no address.
- **`beforeSignUp`** runs at upgrade, at both request and confirm, with the address being adopted. That is when there is an address to judge, so domain allowlists and invite gates apply to upgrades unchanged. It does not run at anonymous creation.

## Rate Limits

Creating an anonymous account costs the caller nothing, not even an inbox, and every accepted request inserts a row. So `POST /auth/anonymous` has its own, tight default: **30 per hour per IP and table**. Override it with `AuthTableRateLimits.anonymousSignUpPolicy()`. Resume is throttled per IP like refresh. The upgrade routes use the send-code and confirm policies, plus the one-code-per-address-per-minute limit OTP already has. See [Auth Rate Limits](/rate-limiting/auth-rate-limits).
