---
title: Config Flavors
description: How to manage dev, staging, and production configurations with flavors.
---

A flavor is a named configuration variant — `dev`, `staging`, `prod`, or any name you choose. Pass it via `--flavor <name>` to `zonai serve`, `zonai compile`, and `zonai build` to select the matching config file and `.env` file.

## Naming Convention

Config files follow a `<base>.<flavor>.dart` naming pattern:

```
lib/src/config/
  db_config.dart          # Base config (no flavor)
  db_config.dev.dart      # Loaded with --flavor dev
  db_config.prod.dart     # Loaded with --flavor prod
```

If a flavor-specific file doesn't exist, Zonai falls back to `db_config.dart`. Multiple files in the config directory are all compiled together.

## .env Files and Flavors

`.env` files work the same way:

```
.env              # Default
.env.dev          # Loaded with --flavor dev
.env.prod         # Loaded with --flavor prod
```

## How Secrets Get Baked In

Worker code uses `const String.fromEnvironment('MY_SECRET')` to read a value. At compile time, Zonai passes all loaded env var values as `--define` flags to `dart compile exe`. The resulting binary contains the literal value — the `.env` file is no longer needed at runtime.

This means the dev and prod binaries have different secrets baked in. Never deploy a binary compiled with dev secrets to production.

## Example Setup

**`lib/src/config/db_config.dev.dart`:**

```dart
AppConfig main() => AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
  baseUrl: 'http://localhost:8080',
  jwtExpiresIn: const Duration(hours: 1),  // short lifetime for dev
);
```

**`lib/src/config/db_config.prod.dart`:**

```dart
AppConfig main() => AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
  baseUrl: 'https://api.myapp.com',
  email: EmailConfig(
    host: const String.fromEnvironment('SMTP_HOST'),
    port: 587,
    username: const String.fromEnvironment('SMTP_USER'),
    password: const String.fromEnvironment('SMTP_PASS'),
    from: EmailAddress(address: 'no-reply@myapp.com', name: 'My App'),
  ),
);
```

**Running with a flavor:**

```bash
# Dev
zonai serve --flavor dev

# Production build
zonai build --flavor prod --release
```

<Info>

Forgetting `--flavor` causes the base `db_config.dart` to be used, which may have wrong or missing credentials. Always specify `--flavor` explicitly and treat the base file as a template.

</Info>
