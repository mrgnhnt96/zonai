---
title: App Config
description: The AppConfig class — secrets, SMTP, JWT settings, and more.
---

`AppConfig` holds all runtime configuration for the Zonai server. Create it in `lib/src/config/db_config.dart` (or a flavor-specific variant). The config worker compiles this file — any change requires recompiling workers.

See [Config Flavors](/core-concepts/config-flavors) for how to use different configs per environment.

## Required Fields

| Field            | Type     | Description                                                                                        |
| ---------------- | -------- | -------------------------------------------------------------------------------------------------- |
| `appName`        | `String` | Human-readable application name. Used in email templates and logs.                                 |
| `jwtSecret`      | `String` | Secret used to sign and verify JWTs. Must be a strong random string. Use `String.fromEnvironment`. |
| `passwordSecret` | `String` | Used in Argon2id password hashing. Must be unique per project. Use `String.fromEnvironment`.       |

<Info>

`passwordSecret` is separate from `jwtSecret`. Never use the same value for both. To rotate `passwordSecret` without invalidating existing passwords, add the old value to `previousPasswordSecrets` in your app config before removing it.

</Info>

## Optional Fields

### Base URL

```dart in:app-config
baseUrl: 'https://api.myapp.com',  // default: 'http://localhost:8080'
```

The public-facing URL of the server. Used to build links in auth emails (password reset, magic link, email verification). Must match where clients can reach the server.

### JWT Lifetime

```dart in:app-config
jwtExpiresIn: const Duration(days: 14),  // default: 14 days
```

Global token lifetime for all auth tables. To override per auth table, set `jwtExpiresIn` on the table's `AuthOperations` class — see [Auth Operations](/operations/auth-operations).

### Secret Rotation

```dart in:app-config
previousJwtSecrets: ['old-secret-1', 'old-secret-2'],
previousPasswordSecrets: ['old-password-secret'],
```

Tokens signed with a previous JWT secret are still accepted during a rotation window. Previous password secrets allow verifying passwords hashed with old secrets before users reset.

### Email / SMTP

```dart in:app-config
email: EmailConfig(
  host: const String.fromEnvironment('SMTP_HOST'),
  port: 587,
  username: const String.fromEnvironment('SMTP_USER'),
  password: const String.fromEnvironment('SMTP_PASS'),
  from: EmailAddress(address: 'no-reply@myapp.com', name: 'My App'),
  ssl: false,  // use true for port 465
),
```

Required for any transactional email. Without this, all `email.send.*` calls will throw. See [SMTP Setup](/email/smtp-setup).

### Photos

```dart in:app-config
photos: PhotosConfig(
  maxBytes: 5 * 1024 * 1024,  // 5 MB
  allowedMimeTypes: [ImageMimeType.jpeg, ImageMimeType.png, ImageMimeType.webp],
),
```

Constrains photo uploads before they reach the rules worker.

### Trusted Proxy

```dart in:app-config
trustedProxy: TrustedProxyConfig(
  headers: ['x-forwarded-for'],
  useLeftmostIp: false,  // default: use rightmost (safer)
),
```

Required for correct client IP resolution behind a reverse proxy or load balancer. See [Trusted Proxies](/rate-limiting/trusted-proxies).

## Minimal Example

```dart in:project-file
AppConfig main() => AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
);
```

## Full Example

```dart in:project-file
AppConfig main() => AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
  baseUrl: const String.fromEnvironment('BASE_URL', defaultValue: 'http://localhost:8080'),
  jwtExpiresIn: const Duration(days: 30),
  email: EmailConfig(
    host: const String.fromEnvironment('SMTP_HOST'),
    port: 587,
    username: const String.fromEnvironment('SMTP_USER'),
    password: const String.fromEnvironment('SMTP_PASS'),
    from: EmailAddress(address: 'no-reply@myapp.com', name: 'My App'),
  ),
  photos: PhotosConfig(maxBytes: 10 * 1024 * 1024),
  trustedProxy: TrustedProxyConfig(headers: ['x-forwarded-for']),
);
```
