---
title: Environment & Secrets
description: How secrets are handled at compile time and what to do in production.
---

## The Compile-Time Secret Model

Zonai's security model bakes secrets into worker binaries at compile time. `String.fromEnvironment('SECRET')` reads the value when `dart compile exe` runs — not when the server starts. The resulting binary contains the secret literal; no `.env` file is needed on the production server.

**Trade-off:** Changing a secret requires recompiling and redeploying the workers.

## Secrets in Production

Build workers with the production `.env.prod` file on your build machine (not on the production server):

```sh
# On the build machine, with .env.prod present
zonai build --flavor prod --release
# Deploy only the build/ directory — no source, no .env files
rsync -avz build/ user@server:/opt/myapp/
```

The `build/` bundle contains all baked-in secrets. Treat it like a signed binary, not source code.

## What to Store in .env.prod

| Variable | Description |
|----------|-------------|
| `JWT_SECRET` | Long random string (min. 32 characters) |
| `PASSWORD_SECRET` | Long random string, different from `JWT_SECRET` |
| `SMTP_HOST` | SMTP server hostname |
| `SMTP_PORT` | SMTP port |
| `SMTP_USERNAME` | SMTP username |
| `SMTP_PASSWORD` | SMTP password or API key |

Add any other values your `AppConfig` reads via `String.fromEnvironment`.

## Rotating Secrets

1. Update the value in `.env.prod`
2. Rebuild: `zonai build --flavor prod --release`
3. Deploy the new bundle

**JWT secret rotation:** Set the new value as `jwtSecret` and move the old value into `previousJwtSecrets` in `AppConfig`. Existing tokens remain valid until they expire; new tokens are signed with the new secret.

**Password secret rotation:** Set the new value as `passwordSecret` and move the old value into `previousPasswordSecrets` in `AppConfig`. Existing password hashes are still verifiable against the previous secret; new passwords are hashed with the new one.

## Security Best Practices

- Never commit `.env.prod` to version control — add it to `.gitignore`
- Use a secrets manager (AWS Secrets Manager, HashiCorp Vault, GitHub Actions secrets) to inject values into `.env.prod` during the CI/CD build step
- Restrict access to the build machine where `.env.prod` is present
- Never include `.env.prod` or source files in the production server deployment
