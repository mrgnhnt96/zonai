---
title: Building for Production
description: How to create a production deployment bundle with zonai build.
---

## Build Command

```sh
zonai build --flavor prod --release
```

This creates a `build/` directory containing everything needed to run on a server. No Dart SDK is required on the target machine.

<Info>

Production bundles include the same **live stream** routes as local serve (`/db/stream*`). Clients should use `zonai_client` `db.listen` in production too — [Streaming](/operations/streaming).

</Info>

## What Gets Bundled

```
build/
├── zonai                    # Project-linked server + CLI (ops/rules in-process)
├── .zonai/executables/      # Worker binaries (config, extensions, rate limits, crons, …)
├── migrations/              # SQL migration files
├── email_templates/         # HTML email templates
└── zonai.yaml               # Project configuration
```

**Not included:** source code, the SQLite database, `.env` files (secrets are baked in at compile time).

`build/zonai` is compiled from your project (generated `project_main.dart`). It is not a generic downloaded CLI binary.

The OpenAPI spec is embedded in the server binary, so `/swagger.json` and `/swagger.yaml` work in production without shipping a separate `public/` directory. See [OpenAPI Specification](/api/openapi-spec).

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
