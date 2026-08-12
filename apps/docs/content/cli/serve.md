---
title: zonai serve
description: Start the HTTP server with optional hot-reload and file watching.
---

Start the Zonai HTTP server.

```sh
zonai serve [flags]
```

Run from a project root, the CLI re-execs into a **project entry** (JIT:
`.dart_tool/zonai/project_main.dart`, or AOT `.zonai/zonai` with `--release`)
so operations and rules run **in-process**. The published release binary stays
in-process and uses Mailman workers for ops/rules. From `build/`, run the
project-linked `./zonai serve --release`.

## Flags

| Flag                  | Description                                                     | Default                              |
| --------------------- | --------------------------------------------------------------- | ------------------------------------ |
| `--host <address>`    | Bind address (see [Server Binding](/deployment/server-binding)) | `zonai.yaml` value, then `localhost` |
| `--port <number>`     | HTTP port                                                       | `zonai.yaml` value, then `8080`      |
| `--flavor <name>`     | Config flavor to load                                           | (none)                               |
| `--release`           | Production mode — skip watchers and recompile                   | `false`                              |
| `--no-auto-migrate`   | Skip applying pending migrations on startup                     | `false`                              |
| `-c, --config <path>` | Path to a custom `zonai.yaml`                                   | Auto-detected                        |

## Startup Sequence

1. Load `zonai.yaml` and resolve all paths
2. Ensure project entry / workers are ready (dev mode may compile)
3. Apply pending migrations (unless `--no-auto-migrate`)
4. Start worker processes still used (config, extensions, rate limits, crons; ops/rules unless `ZONAI_FORCE_WORKERS=1`)
5. Open the HTTP listener

## Dev Mode

In dev mode (the default), Zonai watches worker source directories and recompiles
affected **worker** binaries. Ops/rules are linked into the running project
entry — restart `serve` after editing them so the new code loads.

**Keyboard shortcuts in dev mode:**

| Key | Action                                         |
| --- | ---------------------------------------------- |
| `c` | Manually recompile all workers / regenerate entry |
| `m` | Generate and apply database migrations         |
| `p` | Ping all workers and print their health status |
| `q` | Graceful shutdown                              |

## Release Mode

With `--release`, Zonai does not watch sources or recompile. Use a
project-linked binary from `zonai build` (typical: `cd build && ./zonai serve
--release`) or a prior `compile --release` plus project binary under
`.zonai/zonai`.

## Examples

```sh
# Dev mode with defaults (JIT project entry)
zonai serve

# Dev mode on a custom port
zonai serve --flavor dev --port 9000

# IPv4 loopback only (e.g. behind a reverse proxy)
zonai serve --host 127.0.0.1

# Production mode from a build/ bundle
cd build && ./zonai serve --release --flavor prod
```

The default `host: localhost` binds dual-stack on `::`, so IPv4 and IPv6 clients (including emulators via `10.0.2.2`) work without overrides. See [Server Binding](/deployment/server-binding).

Set `ZONAI_FORCE_WORKERS=1` to run ops/rules via Mailman workers instead of in-process dispatch.
