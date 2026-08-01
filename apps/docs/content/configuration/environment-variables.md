---
title: Environment Variables
description: Compile-time secrets via .env, plus optional runtime ZONAI_* tuning knobs.
---

Zonai uses environment variables in **two** ways:

1. **Compile-time secrets** — baked into binaries from `.env` / `--dart-define` via `String.fromEnvironment`. Production does not need a `.env` file on the server.
2. **Runtime tuning** — a small set of `ZONAI_*` process environment variables read when the server starts (not baked into the binary).

## Compile-time secrets (`.env`)

Your Dart code reads a value at compile time:

```dart
jwtSecret: const String.fromEnvironment('JWT_SECRET'),
```

When Zonai compiles workers or the project binary, it reads your `.env` file and passes each value to `dart compile exe` as a compile-time define (`-Dkey=value`). The compiled binary contains the literal value. If `JWT_SECRET` is not set, the compiled binary will contain an empty string — Zonai logs an error at startup for missing required fields.

This is an implementation detail, not a CLI flag — `zonai compile` and `zonai build` do not read `-D`/`--define` themselves. To override a value, edit `.env` (or `.env.<flavor>`, see below) or use `--dart-define` (see [CLI Overrides](#cli-overrides)).

Changing a secret requires recompiling and redeploying (`zonai build` / `compile`).

## Runtime tuning (`ZONAI_*`)

These are read from the process environment at serve time. They are **not** loaded from `.env` unless you export them yourself in the shell or process manager.

| Variable | Values | Default | Purpose |
|----------|--------|---------|---------|
| `ZONAI_FORCE_WORKERS` | `1` / `true` | unset | Force ops/rules through Mailman workers instead of in-process dispatch |
| `ZONAI_WORKER_TRANSPORT` | `auto`, `process`, `isolate` | `auto` | How Mailman talks to ops/rules workers when workers are used (`auto` prefers isolate/SendPort when a snapshot exists, else process MessagePack) |
| `ZONAI_WORKER_POOL_SIZE` | positive int | `1` | Number of OS processes per Mailman pool (ops/rules/extensions). Higher may help concurrent writes; often hurts pure list |
| `ZONAI_HTTP_WORKERS` | positive int | `1` | HTTP accept isolates. **`>1` currently regresses list throughput** against one SQLite file — keep `1` unless you know you need otherwise |

Example:

```bash
ZONAI_FORCE_WORKERS=1 ZONAI_WORKER_TRANSPORT=process ./zonai serve --release
```

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
