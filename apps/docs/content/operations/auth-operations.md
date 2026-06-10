---
title: Auth Operations
description: Customizing JWT claims, password-reset, OTP, and magic link configuration.
---

Auth operations customize what gets embedded in JWTs and configure auth flow details like password reset link URLs and OTP expiry times. They live in the same operations file as any other table customization.

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

Without any overrides, this is a no-op. Add overrides as needed.

## Adding JWT Claims

Override `addClaims` to embed additional data in the JWT issued on sign-in, sign-up, OTP verify, and magic link verify:

```dart
@override
Future<Claims> addClaims({required Jwt jwt}) async {
  return Claims({
    'is_awesome': true,
    'plan': 'pro',
  });
}
```

The JWT parameter contains the standard claims (including `userId`). You can use `jwt.userId` to fetch the user row and include dynamic data. The returned claims are merged into the JWT payload and accessible in rules and extensions via `jwt?.claims['plan']`.

## Per-Table JWT Lifetime

Override `jwtExpiresIn` to use a different token lifetime than the global `AppConfig.jwtExpiresIn`:

```dart
@override
Duration? get jwtExpiresIn => const Duration(hours: 8);  // shorter than global default
```

Return `null` to fall back to the global `AppConfig.jwtExpiresIn`.

## Password Reset Configuration

Override `resetPasswordConfig` to customize the reset link URL and token expiry:

```dart
@override
ResetPasswordConfig get resetPasswordConfig => ResetPasswordConfig(
  path: '/reset-password',  // appended to AppConfig.baseUrl
  expiresIn: const Duration(hours: 1),
);
```

The full reset link will be `{baseUrl}{path}?token={token}`.

## Email Verification Configuration

Override `verifyEmailConfig` to customize the verify-email link:

```dart
@override
VerifyEmailConfig get verifyEmailConfig => VerifyEmailConfig(
  path: '/verify-email',
  expiresIn: const Duration(hours: 24),
);
```

## Magic Link Configuration

Override `magicLinkConfig` to customize the magic link redirect URL and expiry:

```dart
@override
MagicLinkConfig get magicLinkConfig => MagicLinkConfig(
  path: '/auth/callback',
  expiresIn: const Duration(minutes: 10),
);
```

After the user clicks the link, Zonai validates the token and redirects to `{baseUrl}{path}?token={jwt}`.
