---
title: Environment Variables
description: Compile-time secrets via .env (no --dart-define-from-file needed), plus optional runtime ZONAI_* tuning knobs.
---

Zonai uses environment variables in **two** ways:

1. **Compile-time secrets** — baked into binaries from `.env` / `--dart-define` via `String.fromEnvironment`. Production does not need a `.env` file on the server.
2. **Runtime tuning** — a small set of `ZONAI_*` process environment variables read when the server starts (not baked into the binary).

## Compile-time secrets (`.env`)

Your Dart code reads a value at compile time:

```dart in:expression
AppConfig(
  appName: 'My App',
  jwtSecret: const String.fromEnvironment('JWT_SECRET'),
  passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
)
```

When Zonai compiles workers or the project binary, it reads your `.env` file and passes each value to `dart compile exe` as a compile-time define (`-Dkey=value`). The compiled binary contains the literal value. If `JWT_SECRET` is not set, the compiled binary will contain an empty string — Zonai logs an error at startup for missing required fields.

This is an implementation detail, not a CLI flag — `zonai compile` and `zonai build` do not read `-D`/`--define` themselves. To override a value, edit `.env` (or `.env.<flavor>`, see below) or use `--dart-define` (see [CLI Overrides](#cli-overrides)).

Changing a secret this way requires recompiling and redeploying (`zonai build` / `compile`).

### Overriding a baked-in secret at runtime

`JWT_SECRET`, `PASSWORD_SECRET`, `PREVIOUS_JWT_SECRETS` and `PREVIOUS_PASSWORD_SECRETS` are also read from the **process environment** when the server starts, and the process environment wins over the compiled-in value. An empty or whitespace-only value is ignored rather than applied, so a wrapper script that expands an unset variable cannot blank out a working config. The two `PREVIOUS_*` variables take a comma-separated list.

This matters because a compiled binary contains its defines in plain text — `strings` on the artifact recovers the signing key, and anyone who can read the artifact can then mint tokens for any user. Leaving the secrets out of `.env` entirely and injecting them through the environment ships a binary that contains no secret at all:

```bash
JWT_SECRET="$(openssl rand -base64 48)" \
PASSWORD_SECRET="$(openssl rand -base64 48)" \
  ./zonai serve --release
```

### Secret requirements

`AppConfig.validate()` runs at startup and **fails the process** — it does not warn — if either secret is:

- empty
- a placeholder or well-known value (`change-me-*`, `jwt`, `password`, `secret`, `unconfigured`, …)
- shorter than 32 characters (HS256 signs with a 256-bit key)
- built from fewer than 8 distinct characters
- the same value as the other secret, or listed in its own `previous*Secrets`

`openssl rand -base64 48` produces something acceptable.

## Runtime tuning (`ZONAI_*`)

These are read from the process environment at serve time. They are **not** loaded from `.env` unless you export them yourself in the shell or process manager.

| Variable | Values | Default | Purpose |
|----------|--------|---------|---------|
| `ZONAI_FORCE_WORKERS` | `1` / `true` | unset | Force ops/rules through Mailman workers instead of in-process dispatch |
| `ZONAI_WORKER_TRANSPORT` | `auto`, `process`, `isolate` | `auto` | How Mailman talks to ops/rules workers when workers are used (`auto` prefers isolate/SendPort when a snapshot exists, else process MessagePack) |
| `ZONAI_WORKER_POOL_SIZE` | positive int | `1` | Number of OS processes per Mailman pool (ops/rules/extensions). Higher may help concurrent writes; often hurts pure list |
| `ZONAI_HTTP_WORKERS` | positive int | `1` | HTTP accept isolates. **`>1` currently regresses list throughput** against one SQLite file — keep `1` unless you know you need otherwise |
| `ZONAI_INSECURE_TEST_MODE` | any value except `0`/`false`/`no`/`off` | unset | Makes emailed auth challenges predictable for automated tests: the OTP is always `123456` and each link carries a fixed secret. `zonai serve` **refuses to start** while this is set, and every challenge issued under it logs an error. Anyone who knows a user's email address can sign in as them, so it is only for a harness that drives `ZonaiDb` directly |

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

## There Is No `--dart-define-from-file`

If you are looking for Flutter's `--dart-define-from-file`, Zonai has no such flag and does not need one: **the env file is the default input, not something you point a flag at.** Every command that compiles — `zonai build`, `zonai compile`, and the worker rebuilds `zonai serve` / `zonai dev` trigger — reads `.env` (or `.env.<flavor>` when `--flavor` is passed) from the directory you run the command in, and turns each line into a `-D` define for `dart compile exe`.

| Reaching for | Do this instead |
|---|---|
| `--dart-define-from-file=env.json` | Nothing — put the keys in `.env`, it is loaded automatically |
| A different file per environment | Name it `.env.<flavor>` and pass `--flavor <flavor>` |
| A file in a non-standard location | Run the command from that directory, or copy/symlink it to `.env` there |
| One-off keys, no file | `--dart-define KEY=VALUE`, repeated per key |

Two things this changes:

- **The file is `KEY=VALUE` lines, not JSON.** `--dart-define-from-file` takes a `.json` (or `.env`) file; Zonai's loader is the [.env format above](#env-file-format) — one `KEY=VALUE` per line, `#` comments, optional quotes around values with spaces. A JSON file will not load as defines.
- **Unknown flags are silently ignored.** Zonai's argument parser accepts any `--flag value` pair and drops the ones no command reads. `zonai build --dart-define-from-file env.json` therefore exits successfully, warns about nothing, and injects **zero** defines from that file — every `String.fromEnvironment` falls back to its `defaultValue` (an empty string when there isn't one). If defines appear to be missing from a build, check the flag name before anything else.

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
# Generate each with: openssl rand -base64 48
# These exact values are rejected at startup, which is the point of an example.
JWT_SECRET=replace-with-random-32-char-string
PASSWORD_SECRET=replace-with-different-random-string
SMTP_HOST=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USER=apikey
SMTP_PASS=replace-with-api-key
```

## .gitignore

```text
.env
.env.*
```

Add these lines to `.gitignore`. Only `.env.example` should be committed.
