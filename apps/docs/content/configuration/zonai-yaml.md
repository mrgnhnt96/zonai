---
title: zonai.yaml Reference
description: Every configuration key available in zonai.yaml.
---

`zonai.yaml` is the project configuration file, placed at the project root next to `pubspec.yaml`. It controls source directory paths, server binding, and build targets.

All paths are relative to the directory containing `zonai.yaml`. CLI flags override any value set in this file (e.g. `--port` overrides `port:`).

## Required Fields

| Key | Description |
|-----|-------------|
| `version` | Semantic version string (e.g. `0.1.0`). Zonai uses this to verify CLI/project compatibility. |

## Path Fields

All paths are optional. Zonai uses sensible defaults so you only need to set a path if you deviate from the standard layout.

| Key | Default | Points To |
|-----|---------|-----------|
| `schemasPath` | `lib/src/schemas` | Table definitions |
| `configPath` | `lib/src/config` | AppConfig files |
| `operationsPath` | `lib/src/operations` | Custom operations |
| `rulesPath` | `lib/src/rules` | Authorization rules |
| `extensionsPath` | `lib/src/extensions` | Lifecycle hooks |
| `rateLimitPath` | `lib/src/rate_limit` | Rate limit policies |
| `cronsPath` | `lib/src/crons` | Cron job definitions |
| `emailTemplatesPath` | `lib/src/email_templates` | HTML email templates |
| `migrationsPath` | `.zonai/migrations` | Generated SQL migration files |
| `dataPath` | `.zonai/data` | SQLite database directory |
| `imagesPath` | `<dataPath>/images` | Uploaded photo files, plus the dashboard's [`favicon.ico` and `logo.png`](/dashboard/branding) |

## Storage Fields

| Key | Default | Description |
|-----|---------|-------------|
| `logDatabaseMaxSize` | *(no limit)* | Hard ceiling on the log database file. A positive byte count, optionally suffixed `b`, `kb`, `mb`, `gb` or `tb` (powers of 1024) — e.g. `512mb`. |

### `logDatabaseMaxSize`

`_log` lives in [its own database file](/cli/db#where-logs-are-stored), which is what makes a ceiling on it expressible at all: SQLite's cap bounds a *file*, so on a shared database it would be hit by whichever write arrived first — your application's inserts just as easily as a log line.

**It is off by default, and that is deliberate.** Once the ceiling is reached, log writes fail and keep failing until retention frees space. That costs you observability at exactly the moment something is going wrong, so it is not imposed on a project that did not ask for it. Retention, the nightly reclaim, and the disk-full error already handle the ordinary case.

Set it when you want a guarantee that this one table can never be what fills a volume:

```yaml
logDatabaseMaxSize: 512mb
```

Pick a size that is generous relative to your retention window — the cap is a backstop for a runaway, not a substitute for retention. When it is reached, the server keeps serving requests and keeps printing to the console; it prints one line to stderr saying log records are no longer reaching the database, and the dashboard's log view stops gaining entries.

Removing the key lifts the cap on the next server start. Nothing is stored in the database file, so there is no reset step. An unparseable value is rejected at startup rather than ignored — a ceiling you believe you have but do not is worse than none.

There is no equivalent for `_rate_limit`: it is bounded by its own retention window rather than by growth, and capping it would start failing the writes that enforce your rate limits.

## Server Fields


| Key | Default | Description |
|-----|---------|-------------|
| `host` | `localhost` | Bind address. When `localhost`, the server binds dual-stack on `::` (IPv4 + IPv6). Use `127.0.0.1` for IPv4 loopback only or `0.0.0.0` for all IPv4 interfaces. |
| `port` | `8080` | HTTP port. |

CLI `--host` and `--port` flags take precedence over these values. See [Server Binding](/deployment/server-binding) for examples.

## Build Settings

The optional `buildSettings` block enables cross-compilation:

| Key | Default | Values |
|-----|---------|--------|
| `targetOs` | Current OS | `linux`, `macos`, `windows` |
| `targetArch` | Current arch | `arm64`, `x64` |

Use this when building on macOS to deploy to a Linux server.

## Complete Example

```yaml
version: 0.1.0

# Server binding
host: localhost
port: 8080

# Source paths (all have defaults — only set if you deviate)
schemasPath: lib/src/schemas
configPath: lib/src/config
operationsPath: lib/src/operations
rulesPath: lib/src/rules
extensionsPath: lib/src/extensions
rateLimitPath: lib/src/rate_limit
cronsPath: lib/src/crons
emailTemplatesPath: lib/src/email_templates

# Generated paths
migrationsPath: .zonai/migrations
dataPath: .zonai/data
imagesPath: .zonai/data/images

# Optional hard ceiling on the log database (omit for no limit)
logDatabaseMaxSize: 512mb

# Cross-compilation (omit to build for current platform)
buildSettings:
  targetOs: linux
  targetArch: x64
```

**Minimal `zonai.yaml`** (most projects only need this):

```yaml
version: 0.1.0
```
