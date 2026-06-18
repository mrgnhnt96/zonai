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
| `imagesPath` | `<dataPath>/images` | Uploaded photo files |

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

# Cross-compilation (omit to build for current platform)
buildSettings:
  targetOs: linux
  targetArch: x64
```

**Minimal `zonai.yaml`** (most projects only need this):

```yaml
version: 0.1.0
```
