---
title: Workers
description: What workers are, why they exist, and how Zonai uses them.
---

A **worker** is a compiled Dart native executable that handles one category of logic for the Zonai server. Workers talk to the host over IPC (framed MessagePack on stdin/stdout, with an isolate/SendPort option for ops/rules).

**Ops and rules are different on the default path.** `zonai serve` and `zonai build` produce a **project-linked** binary (or JIT `project_main` in development) that calls your operations and authorization code **in-process** — no IPC hop on create/list. Worker `.exe` files for ops/rules are still compiled for `zonai ping`, compatibility, and the `ZONAI_FORCE_WORKERS=1` escape hatch.

Config, extensions, rate limits, and crons still run as worker processes.

## Worker Types

| Worker | Source Directory | Responsibility | Default runtime |
|--------|------------------|----------------|-----------------|
| `rules` | `lib/src/rules/` | Authorization for each operation | In-process (project binary) |
| `operations` | `lib/src/operations/` | SQL generation from HTTP payloads | In-process (project binary) |
| `extensions` | `lib/src/extensions/` | Lifecycle hooks around mutations and auth | Worker IPC |
| `rate_limit` | `lib/src/rate_limit/` | Per-IP request quotas | Worker IPC |
| `crons` | `lib/src/crons/` | Scheduled background jobs | Worker IPC |
| `config` | `lib/src/config/` | App-wide settings (JWT, SMTP, …) | Worker IPC |

## Why Workers?

**Type safety.** Business logic is written in Dart and compiled to native code. If your code references a column that doesn't exist, `dart compile` catches it before the server serves traffic.

**Isolation.** A panic in extension or cron code does not crash the HTTP server. Worker failures are caught and reported without taking down the process.

**Correctness.** Configuration errors (missing SMTP credentials, wrong JWT secret) are detected at compile time.

**Speed (ops/rules).** Linking ops and rules into the project binary avoids per-request IPC for SQL generation and authorization — the hot path for CRUD.

## The Compile Step

Workers compile from `lib/src/` into `.zonai/executables/`. `zonai build` also compiles the project-linked `build/zonai`.

```bash
# Compile all workers (and regenerate project_main)
zonai compile

# Full deploy bundle: workers + project binary + migrations
zonai build --flavor prod --release
```

Any change to rules, operations, extensions, config, rate_limit, or crons requires recompilation. For **in-process** ops/rules, restart `zonai serve` (or rebuild) so the linked entry reloads.

## Hot-Reload in Development

`zonai serve` (without `--release`) watches worker source directories. When a Dart file for a **worker-backed** type changes, Zonai recompiles that worker and routes future requests to the new binary — no full server restart for those workers.

Press `c` to force a recompile of all workers (and regenerate `project_main`) at any time.

Ops/rules source changes update generated entry files, but the running process still has the old linked code until you restart serve.

## Worker Health

On startup, Zonai starts the worker processes it still uses and can ping them for readiness. Press `p` in dev mode to manually ping workers.

With `ZONAI_FORCE_WORKERS=1`, ops and rules also run as Mailman workers (same as older Zonai versions).
