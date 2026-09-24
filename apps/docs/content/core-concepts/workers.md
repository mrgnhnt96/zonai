---
title: Workers
description: What workers are, why they exist, and how Zonai uses them.
---

A **worker** is a compiled Dart native executable that handles one category of logic for the Zonai server. Workers talk to the host over IPC (framed MessagePack on stdin/stdout, with an isolate/SendPort option for ops/rules).

**Ops and rules can also run in-process.** When your project depends on `package:zonai` itself, `zonai serve` (run from source) and `zonai build` produce a **project-linked** binary that calls your operations and authorization code in-process — no IPC hop on create/list/stream. A project scaffolded by `zonai dev` depends only on `zonai_schema`, so with the installed CLI its ops and rules run as workers like everything else. The two paths behave identically; `ZONAI_FORCE_WORKERS=1` forces the worker path even when linking is possible.

Config, extensions, rate limits, and crons always run as worker processes.

## Worker Types

| Worker | Source Directory | Responsibility | Runtime |
|--------|------------------|----------------|-----------------|
| `rules` | `lib/src/rules/` | Authorization for each operation | Worker, or in-process when linked |
| `operations` | `lib/src/operations/` | SQL generation from HTTP payloads | Worker, or in-process when linked |
| `extensions` | `lib/src/extensions/` | Lifecycle hooks around mutations and auth | Worker IPC |
| `rate_limit` | `lib/src/rate_limit/` | Per-IP request quotas | Worker IPC |
| `crons` | `lib/src/crons/` | Scheduled background jobs | Worker IPC |
| `config` | `lib/src/config/` | App-wide settings (JWT, SMTP, …) | Worker IPC |

## Why Workers?

**Type safety.** Business logic is written in Dart and compiled to native code. If your code references a column that doesn't exist, `dart compile` catches it before the server serves traffic.

**Isolation.** A panic in extension or cron code does not crash the HTTP server. Worker failures are caught and reported without taking down the process.

**Correctness.** Type errors in your config, rules, hooks and jobs fail `dart compile` rather than a request; invalid config (an empty or weak secret, an unusable push setup) stops the server at startup instead of surfacing on the first request that needs it.

**Speed (ops/rules).** When linking is possible, running ops and rules in-process avoids per-request IPC for SQL generation and authorization — the hot path for CRUD and live streams.

## The Compile Step

Workers compile from `lib/src/` into `.zonai/executables/` (`build/.zonai/executables/` for `zonai build`). Every worker is compiled with the defines from the selected `.env` file — see [Config Flavors](/core-concepts/config-flavors).

```bash
# Compile all workers (and regenerate project_main)
zonai compile

# Full deploy bundle: workers + project binary + migrations
zonai build --flavor prod --release
```

Any change to rules, operations, extensions, config, rate_limit, or crons requires recompilation. When ops/rules are linked in-process, restart `zonai serve` (or rebuild) so the linked entry reloads.

## Hot-Reload in Development

`zonai serve` (without `--release`) watches worker source directories. When a Dart file for a **worker-backed** type changes, Zonai recompiles that worker and routes future requests to the new binary — no full server restart for those workers.

Press `c` to force a recompile of all workers (and regenerate `project_main`) at any time.

When ops/rules are linked in-process, source changes update the generated entry files, but the running process keeps the old linked code until you restart serve.

## Worker Health

On startup, Zonai starts the worker processes it still uses and can ping them for readiness. Press `p` in dev mode to manually ping workers.

With `ZONAI_FORCE_WORKERS=1`, ops and rules run as workers even when the binary is project-linked.

## IPC transport

When workers are used, the host talks to them over **framed MessagePack** on stdin/stdout (length-prefixed binary frames — not JSON lines).

For ops/rules workers only, Mailman can instead spawn an **isolate** (AOT snapshot when the host is AOT, or generated Dart source under JIT) and use `SendPort`. Control with `ZONAI_WORKER_TRANSPORT`:

| Value | Behavior |
|-------|----------|
| `auto` (default) | Prefer isolate when a snapshot/entry exists; fall back to process |
| `process` | Always MessagePack pipes to the `.exe` |
| `isolate` | Prefer isolate; fall back to process if spawn fails |

Optional `ZONAI_WORKER_POOL_SIZE` (default `1`) runs multiple OS processes per Mailman pool. See [Environment Variables](/configuration/environment-variables).
