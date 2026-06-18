---
title: zonai serve
description: Start the HTTP server with optional hot-reload and file watching.
---

Start the Zonai HTTP server.

```sh
zonai serve [flags]
```

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
2. Compile workers (dev mode only — skipped with `--release`)
3. Apply pending migrations (unless `--no-auto-migrate`)
4. Start all workers
5. Ping workers to confirm readiness
6. Open the HTTP listener

## Dev Mode

In dev mode (the default), Zonai watches your source directories for changes and recompiles the affected worker automatically. The server stays live while compilation runs — in-flight requests complete before the worker restarts.

**Keyboard shortcuts in dev mode:**

| Key | Action                                         |
| --- | ---------------------------------------------- |
| `c` | Manually recompile all workers                 |
| `m` | Generate and apply database migrations         |
| `p` | Ping all workers and print their health status |
| `q` | Graceful shutdown                              |

## Release Mode

With `--release`, Zonai starts using already-compiled workers. No file watchers, no keyboard shortcuts. Worker binaries must already exist in the build directory — run `zonai build` first.

## Examples

```sh
# Dev mode with defaults
zonai serve

# Dev mode on a custom port
zonai serve --flavor dev --port 9000

# IPv4 loopback only (e.g. behind a reverse proxy)
zonai serve --host 127.0.0.1

# Production mode
zonai serve --release --flavor prod
```

The default `host: localhost` binds dual-stack on `::`, so IPv4 and IPv6 clients (including emulators via `10.0.2.2`) work without overrides. See [Server Binding](/deployment/server-binding).
