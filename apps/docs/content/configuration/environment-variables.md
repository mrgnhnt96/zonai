---
title: Environment Variables
description: How Zonai loads and bakes environment variables into compiled workers.
---

Zonai does not read environment variables at runtime. Instead, secrets are **baked into worker binaries at compile time** using Dart's `String.fromEnvironment`. This means the production server needs no `.env` file — the secrets travel inside the binary.

## How It Works

Your Dart code reads a value at compile time:

```dart
jwtSecret: const String.fromEnvironment('JWT_SECRET'),
```

When Zonai compiles a worker, it reads your `.env` file and passes each value to `dart compile exe` as a compile-time define (`-Dkey=value`). The compiled binary contains the literal value. If `JWT_SECRET` is not set, the compiled binary will contain an empty string — Zonai logs an error at startup for missing required fields.

This is an implementation detail, not a CLI flag — `zonai compile` and `zonai build` do not read `-D`/`--define` themselves. To override a value, edit `.env` (or `.env.<flavor>`, see below) or use `--dart-define` (see [CLI Overrides](#cli-overrides)).

Changing a secret requires recompiling and redeploying the workers.

## .env File Format

Place a `.env` file in the project root (next to `zonai.yaml`):

```bash
# .env
JWT_SECRET=my-dev-jwt-secret-at-least-32-characters
PASSWORD_SECRET=different-long-random-string
BASE_URL=http://localhost:8080

# SMTP (only needed if using email)
SMTP_HOST=localhost
SMTP_PORT=1025
SMTP_USER=
SMTP_PASS=
```

- One `KEY=VALUE` per line
- Lines starting with `#` are comments
- Values with spaces: `APP_NAME="My Great App"`

## Flavor-Specific Files

Each env file is loaded on its own. When `--flavor <flavor>` is active, only `.env.<flavor>` is loaded — `.env` is not read at all. Without a flavor, only `.env` is loaded.

```bash
# .env — loaded when no flavor is specified
JWT_SECRET=dev-secret
BASE_URL=http://localhost:8080

# .env.prod — loaded only with --flavor prod
JWT_SECRET=prod-secret-much-stronger
BASE_URL=https://api.myapp.com
```

Each file must be self-contained with all the variables your workers need.

## CLI Overrides

Pass one-off values without editing `.env` using `--dart-define KEY=VALUE`, repeated for each key:

```bash
zonai build --dart-define BASE_URL=https://staging.example.com --dart-define FEATURE_X=on
```

CLI defines are merged on top of the loaded `.env`/`.env.<flavor>` file and win on key collisions. Use space-separated form (`--dart-define KEY=VALUE`), not `--dart-define=KEY=VALUE` — a joined value that itself contains `=` won't parse correctly.

## What Goes in .env

**Always use `String.fromEnvironment` and `.env`:**

- `JWT_SECRET` — JWT signing key
- `PASSWORD_SECRET` — password hashing key
- SMTP password and any API keys

**Hard-coding is fine:**

- Feature flags
- Non-secret config values
- Public URLs in dev builds

## .env.example

Commit a `.env.example` file with placeholder values so teammates know what variables are needed:

```bash
# .env.example — commit this; do NOT commit .env
JWT_SECRET=replace-with-random-32-char-string
PASSWORD_SECRET=replace-with-different-random-string
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=replace-with-api-key
```

## .gitignore

```
.env
.env.*
```

Add these lines to `.gitignore`. Only `.env.example` should be committed.
