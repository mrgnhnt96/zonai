---
title: Environment & Secrets
description: How secrets are handled at compile time and what to do in production.
---

## Two ways a secret reaches the server

| | Baked in at compile time | Injected at runtime |
| --- | --- | --- |
| How | `.env.<flavor>` on the build machine → `-D` defines → `String.fromEnvironment` | Process environment of `./zonai serve` |
| Applies to | Any value your worker code reads with `String.fromEnvironment` | Only `JWT_SECRET`, `PASSWORD_SECRET`, `PREVIOUS_JWT_SECRETS`, `PREVIOUS_PASSWORD_SECRETS` |
| Changing it | Rebuild and redeploy | Restart the process |
| Where it ends up | In plain text inside every compiled binary in `build/` | Nowhere on disk |

Compile-time defines are the default and cover everything (SMTP passwords, API keys, feature flags). `String.fromEnvironment` is resolved when `dart compile exe` runs, not when the server starts, so no `.env` file is needed on the production server — and editing one there does nothing.

The trade-off is that `strings` on a compiled binary recovers anything baked into it. For the two signing secrets, which let whoever holds them mint a token for any user, prefer runtime injection: leave them out of `.env.prod` and set them in the environment of the serving process. A value set there always wins over the compiled-in one; an empty or whitespace-only value is ignored.

```sh
JWT_SECRET="$(cat /run/secrets/jwt)" \
PASSWORD_SECRET="$(cat /run/secrets/password)" \
  ./zonai serve --release
```

Both secrets are validated at startup (at least 32 characters, not a placeholder, not equal to each other); a failure stops the server. See [Environment Variables](/configuration/environment-variables#secret-requirements).

## Building with production values

Build on a CI runner or build machine that has `.env.prod`, not on the production server:

```sh
zonai build --flavor prod --release
# Deploy only the build/ directory — no source, no .env files
rsync -avz build/ user@server:/opt/myapp/
```

`--flavor prod` reads **only** `.env.prod` — `.env` is not merged in, and a missing `.env.prod` builds with no defines at all (with a warning). See [Config Flavors](/core-concepts/config-flavors).

Treat `build/` (and `.zonai/executables/` locally) like a credential: every binary in it carries whatever was in the env file.

## What to store in .env.prod

| Variable | Description |
|----------|-------------|
| `JWT_SECRET` | Long random string (min. 32 characters) — or omit and inject at runtime |
| `PASSWORD_SECRET` | Long random string, different from `JWT_SECRET` — or omit and inject at runtime |
| `SMTP_HOST`, `SMTP_USER`, `SMTP_PASS` | Whatever names your `EmailConfig` reads — see [SMTP Setup](/email/smtp-setup) |

Add any other values your `AppConfig`, rules, extensions or crons read via `String.fromEnvironment`. Use `defaultValue:` for anything optional; a missing key otherwise compiles to an empty string.

## Rotating secrets

**JWT secret:** set the new value as the current secret and move the old one into `previousJwtSecrets` (or the `PREVIOUS_JWT_SECRETS` environment variable, comma-separated). Existing tokens stay valid until they expire; new tokens are signed with the new secret.

**Password secret:** set the new value as the current secret and move the old one into `previousPasswordSecrets` (or `PREVIOUS_PASSWORD_SECRETS`). Existing password hashes still verify against the previous secret; new passwords are hashed with the new one.

Secrets injected at runtime rotate with a restart. Secrets baked in need `zonai build --flavor prod --release` and a redeploy.

## Security best practices

- Never commit `.env` or `.env.*` — only `.env.example` (see [Environment Variables](/configuration/environment-variables))
- Inject values into `.env.prod` from a secrets manager (GitHub Actions secrets, Vault, AWS Secrets Manager) during the CI build step, or skip the file for the signing secrets and inject them at runtime
- Restrict access to the build machine and to the `build/` artifact
- Never ship `.env.*` or source files to the production server
