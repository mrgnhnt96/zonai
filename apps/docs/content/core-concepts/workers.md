---
title: Workers
description: What workers are, why they exist, and how Zonai uses them.
---

A worker is a compiled Dart native executable that handles one category of logic for the Zonai server. Zonai communicates with workers via IPC (inter-process communication) at request time. Each HTTP request passes through several worker round-trips in sequence.

## Worker Types

| Worker | Source Directory | Responsibility |
|--------|-----------------|----------------|
| `rules` | `lib/src/rules/` | Evaluates authorization for each operation |
| `operations` | `lib/src/operations/` | Generates SQL from HTTP request payloads |
| `extensions` | `lib/src/extensions/` | Runs lifecycle hooks around mutations and auth events |
| `rate_limit` | `lib/src/rate_limit/` | Checks and updates per-IP request quotas |
| `crons` | `lib/src/crons/` | Runs scheduled background jobs on a timer |
| `config` | `lib/src/config/` | Provides app-wide settings (JWT secret, SMTP, etc.) at startup |

## Why Workers?

**Type safety.** All business logic is written in Dart and compiled to native binaries. If your code references a column that doesn't exist, `dart compile` catches it before the server ever starts.

**Isolation.** A panic or bug in your extension code does not crash the HTTP server. Worker failures are caught and reported without taking down the process.

**Correctness.** Configuration errors (missing SMTP credentials, wrong JWT secret) are detected at compile time, not discovered by a 3 AM alert.

## The Compile Step

Workers are compiled from your source files in `lib/src/` into native executables in `.zonai/executables/`.

```bash
# Compile all workers
zonai compile

# Or compile as part of a production build
zonai build --flavor prod --release
```

Any change to rules, operations, extensions, config, rate_limit, or crons requires recompilation before the new code takes effect.

## Hot-Reload in Development

`zonai serve` (without `--release`) watches your source files. When a Dart file in any worker directory changes, Zonai automatically recompiles that worker and routes future requests to the new binary — no server restart needed.

Press `c` to force a recompile of all workers at any time.

## Worker Health

On startup, Zonai launches all worker processes and pings each one to confirm readiness. If any worker fails the ping, the server logs an error and **does not open the HTTP listener** — it will not silently serve requests with a broken rules or operations worker.

Press `p` in dev mode to manually ping all workers and inspect their status.
