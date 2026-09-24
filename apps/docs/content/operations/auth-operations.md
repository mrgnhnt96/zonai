---
title: Auth Operations
description: Customizing JWT claims, token lifetime, and the password-reset, verify-email and magic link links.
---

Auth operations customize what gets embedded in JWTs, how long they last, and where auth email links point. They live in the same operations file as any other table customization, and you only need one when a default below doesn't suit you — an auth table with no operations file already gets every default.

## Enabling Auth Operations

Mix in `AuthOperations` on the operations class for an auth table:

```dart
import 'package:my_app/src/schemas/users.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class UserOperations extends TableOperations<UserTable, User>
    with AuthOperations {
  UserOperations() : super(users);
}

UserOperations main() => UserOperations();
```

Without any overrides, this is a no-op. Override only what you need:

| Override | Default |
| --- | --- |
| `addClaims` | No extra claims |
| `jwtExpiresIn` | `null` — use the global `AppConfig.jwtExpiresIn` (24 hours) |
| `resetPasswordConfig` | Path `/auth/reset-password`, expires in 10 minutes |
| `verifyEmailConfig` | Path `/auth/verify-email`, expires in 24 hours |
| `magicLinkConfig` | Path `/auth/magic-link`, expires in 10 minutes |

## Adding JWT Claims

Override `addClaims` to embed additional data in the JWT issued on sign-in, sign-up, OTP verify, and magic link verify:

```dart in:auth-operations
@override
Future<Claims> addClaims({required Jwt jwt}) async {
  return Claims({
    'is_awesome': true,
    'plan': 'pro',
  });
}
```

The JWT parameter contains the standard claims (including `userId`). You can use `jwt.userId` to fetch the user row and include dynamic data. The returned claims are merged into the JWT payload and accessible in rules and extensions via `jwt?.claims['plan']` — see [JWT Claims](/rules/jwt-claims).

## Per-Table JWT Lifetime

Override `jwtExpiresIn` to use a different token lifetime than the global `AppConfig.jwtExpiresIn`:

```dart in:auth-operations
@override
Duration? get jwtExpiresIn => const Duration(hours: 8);  // shorter than global default
```

Return `null` to fall back to the global `AppConfig.jwtExpiresIn` (24 hours unless you set it — see [App Config](/configuration/app-config)).

## Auth Email Links

Password reset, email verification and magic link emails all carry a link built the same way:

```
{AppConfig.baseUrl}{path}?s=<secret>
```

`path` may also be a full `https://…` URL, used as-is, when the page that handles the link lives on a different origin from `baseUrl`. Zonai does not redirect — the page at that URL reads `s` and posts it to `POST /auth/confirm`. See [Password Auth](/authentication/password-auth) and [Magic Link Auth](/authentication/magic-link-auth) for the exchange, and [Email](/email/built-in-templates) for the templates the links go into.

### Password reset

```dart in:auth-operations
@override
Future<ResetPasswordConfig> resetPasswordConfig() async => ResetPasswordConfig(
  path: '/reset-password',
  expiresIn: const Duration(hours: 1),
);
```

### Email verification

```dart in:auth-operations
@override
Future<VerifyEmailConfig> verifyEmailConfig() async => VerifyEmailConfig(
  path: '/verify-email',
  expiresIn: const Duration(hours: 24),
);
```

### Magic link

```dart in:auth-operations
@override
Future<MagicLinkConfig> magicLinkConfig() async => MagicLinkConfig(
  path: '/auth/callback',
  expiresIn: const Duration(minutes: 10),
);
```

OTP codes are not configured here: they are always six digits and expire after 10 minutes.
