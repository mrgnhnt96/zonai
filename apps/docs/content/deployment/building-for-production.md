---
title: Building for Production
description: How to create a production deployment bundle with zonai build.
---

## Build Command

```sh
zonai build --flavor prod --release
```

This deletes any existing `build/` directory and creates a new one containing everything needed to run on a server. No Dart SDK is required on the target machine.

- `--flavor prod` selects `db_config.prod.dart` and `.env.prod` — see [Config Flavors](/core-concepts/config-flavors).
- `--release` compiles the workers without Dart asserts — see [Release mode](#release-mode).
- `buildSettings` in `zonai.yaml` picks the target OS/architecture — see [Cross-Compilation](/deployment/cross-compilation).

## What Gets Bundled

Paths inside `build/` mirror your project's configured paths; with the defaults:

```
build/
├── zonai                        # Server + CLI (zonai.exe for a Windows target)
├── zonai.yaml                   # Copy of your settings file (host, port, paths)
├── .zonai/
│   ├── executables/             # Worker binaries (config, rules, operations, extensions, rate limits, crons)
│   ├── migrations/              # SQL migrations (<migrationsPath>)
│   ├── data/images/             # favicon.ico / logo.png, if present (<imagesPath>)
│   └── lib/                     # Target's native libraries (cross-compiled builds only)
└── lib/src/email_templates/     # HTML email templates, if any (<emailTemplatesPath>)
```

**Not included:** source code, the SQLite database, and `.env` files — their values are already compiled into the binaries.

`build/zonai` is one of two things, and both serve identically:

- **Project-linked** (when your project resolves `package:zonai`): compiled from your project's generated entry, with operations and rules running in-process.
- **The published `zonai` binary** (the usual case): operations and rules run in the worker binaries beside it. The build log says `Bundling the published zonai binary: <reason>`.

The OpenAPI spec and the `/db/stream*` live-stream routes are built into the server, so `/swagger.json`, `/swagger.yaml` and [`db.listen`](/operations/streaming) work in production without extra files.

## Release mode

`--release` switches Zonai from development to production behavior. Pass it to `build` (or `compile`) when building, and to `serve` when running.

| | Development (default) | `--release` |
| --- | --- | --- |
| Worker compile | `--enable-asserts` — `assert(...)` in your config, rules, extensions, operations, rate limits and crons runs | No asserts |
| `serve` file watchers / recompiling | On — edits recompile workers | Off — serves the binaries already built |
| `serve` keyboard shortcuts (`c`, `m`, `p`, `r`, `q`) | On | Off |
| Generating migrations from schema changes | On | Off |
| Applying pending migration SQL at startup | On | On |

`build/zonai` itself is always compiled without asserts; `--release` controls the workers beside it. A server started with `--release` still shuts down gracefully on `SIGTERM` / `SIGINT`.

Migrations are generated during development and committed; `build` copies them into the bundle, and `serve --release` applies any that are pending when it opens the database. There is no separate migrate step on deploy.

## Pre-Build Checklist

1. `.env.prod` contains every value your code reads with `String.fromEnvironment` — or the signing secrets will be [injected at runtime](/deployment/environment-and-secrets) instead
2. `db_config.prod.dart` reads secrets with `String.fromEnvironment` — never hard-coded
3. `host`/`port` in `zonai.yaml` are what the server should use (usually `0.0.0.0` in a container), and `baseUrl` is the public URL — see [Server Binding](/deployment/server-binding)
4. Pending migration files are committed — they are bundled as-is

## Deploying the Bundle

Copy `build/` to the server:

```sh
rsync -avz build/ user@server:/opt/myapp/
```

Start the server from that directory:

```sh
cd /opt/myapp && ./zonai serve --release
```

The server applies pending migrations and begins accepting requests. To ship changed code, config or env values, run `zonai build --flavor prod --release` again and redeploy the whole directory.

See [Running the Server](/deployment/running-the-server) for process manager setup.
