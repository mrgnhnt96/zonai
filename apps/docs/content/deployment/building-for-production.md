---
title: Building for Production
description: How to create a production deployment bundle with zonai build.
---

## Build Command

```sh
zonai build --flavor prod --release
```

This creates a `build/` directory containing everything needed to run on a server. No Dart SDK is required on the target machine.

## What Gets Bundled

```
build/
├── zonai                    # Compiled Zonai server binary
├── .zonai/executables/      # All compiled worker binaries
├── migrations/              # SQL migration files
├── email_templates/         # HTML email templates
└── zonai.yaml               # Project configuration
```

**Not included:** source code, the SQLite database, `.env` files (secrets are baked in at compile time).

## Pre-Build Checklist

Before running `zonai build`:

1. Ensure `.env.prod` contains all required secrets (`JWT_SECRET`, `PASSWORD_SECRET`, SMTP credentials)
2. Verify `db_config.prod.dart` uses `String.fromEnvironment` for all secrets — never hard-code them
3. Run `zonai compile --flavor prod --release` first to catch compilation errors
4. Review any pending migration files — they will be included in the bundle

## Deploying the Bundle

Copy `build/` to the server:

```sh
rsync -avz build/ user@server:/opt/myapp/
```

Start the server:

```sh
cd /opt/myapp && ./zonai serve --release
```

The server applies pending migrations and begins accepting requests.

See [Running the Server](/deployment/running-the-server) for process manager setup.
