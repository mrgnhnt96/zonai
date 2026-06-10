---
title: zonai compile
description: Compile worker executables without creating a deployment bundle.
---

Compile all worker executables from source and write them to `.zonai/executables/`. Does not create a deployment bundle.

```sh
zonai compile [flags]
```

## Flags

| Flag | Description |
|------|-------------|
| `--flavor <name>` | Config flavor to compile workers with |
| `--release` | Compile without Dart asserts |
| `-c, --config <path>` | Path to a custom `zonai.yaml` |

## Workers Compiled

- `db_config` — config worker
- `db_rules` — rules worker
- `db_operations` — operations worker
- `db_extensions` — extensions worker
- `db_rate_limit` — rate limit worker
- `db_crons` — crons worker

## When to Use Manually

In dev mode (`zonai serve`), Zonai watches source files and recompiles workers automatically — manual `compile` is rarely needed during development. Use it for:

- Setting up a fresh clone before starting the server
- Verifying compilation succeeds in CI
- Updating compiled binaries after discarding changes that left executables stale
- Preparing workers before running `zonai cron run` or `zonai rules` without starting the server

## vs. zonai build

- `zonai compile` — workers only, to `.zonai/executables/`. Use during development.
- `zonai build` — full production bundle with everything needed to deploy. Use for deployment.
