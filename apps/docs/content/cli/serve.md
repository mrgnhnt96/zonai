---
title: zonai serve
description: Start the HTTP server with optional hot-reload and file watching.
---

Start the Zonai HTTP server.

```sh
zonai serve [flags]
```

Run it from the project root (where `zonai.yaml` lives). With the installed
`zonai` binary, operations and rules run in their compiled worker executables
alongside the other workers. Only a project that itself depends on
`package:zonai` gets a generated **project entry** (JIT
`.dart_tool/zonai/project_main.dart`, or AOT `.zonai/zonai` with `--release`)
with operations and rules running in-process. Both behave the same. In
production, run `./zonai serve --release` from a
[`build/` bundle](/deployment/building-for-production).

## Flags

| Flag                  | Description                                                     | Default                              |
| --------------------- | --------------------------------------------------------------- | ------------------------------------ |
| `--host <address>`    | Bind address (see [Server Binding](/deployment/server-binding)) | `zonai.yaml` value, then `localhost` |
| `--port <number>`     | HTTP port                                                       | `zonai.yaml` value, then `8080`      |
| `--flavor <name>`     | Config flavor — picks the config file and `.env.<name>`         | (none)                               |
| `--release`           | Production mode — no watchers, no recompiling, no shortcuts     | `false`                              |
| `--no-auto-migrate`   | Dev only: don't generate migrations from schema changes         | `false`                              |
| `-c, --config <path>` | Path to a custom `zonai.yaml`                                   | Auto-detected                        |

Pending migration SQL is always applied when the database opens, with or
without `--no-auto-migrate` and `--release`. The flag only stops dev mode from
watching `schemasPath` and generating new migrations.

## Dev Mode

In dev mode (the default), Zonai watches worker source directories and recompiles
affected **worker** binaries. When ops/rules are linked into the project entry
(see above), restart `serve` after editing them so the new code loads.

**Keyboard shortcuts in dev mode:**

| Key | Action                                         |
| --- | ---------------------------------------------- |
| `c` | Manually recompile all workers / regenerate entry |
| `m` | Generate and apply database migrations         |
| `p` | Ping all workers and print their health status |
| `r` | Restart the database connection                |
| `q` | Graceful shutdown                              |

## Release Mode

With `--release`, Zonai does not watch sources, recompile, generate
migrations, or read keyboard shortcuts — it serves the binaries that already
exist. Build them first with `zonai build --release` (typical:
`cd build && ./zonai serve --release`) or `zonai compile --release`. The full
list of differences is under
[Release mode](/deployment/building-for-production#release-mode).

## Examples

```sh
# Dev mode with defaults (JIT project entry)
zonai serve

# Dev mode on a custom port
zonai serve --flavor dev --port 9000

# IPv4 loopback only (e.g. behind a reverse proxy)
zonai serve --host 127.0.0.1

# Production mode from a build/ bundle
cd build && ./zonai serve --release
```

The default `host: localhost` binds `127.0.0.1`: reachable from this machine (and the Android emulator via `10.0.2.2`) but not from the network. Pass `--host 0.0.0.0` to expose it. See [Server Binding](/deployment/server-binding).

Set `ZONAI_FORCE_WORKERS=1` to run ops/rules via workers even when the project entry is linked.
