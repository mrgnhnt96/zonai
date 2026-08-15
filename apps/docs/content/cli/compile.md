---
title: zonai compile
description: Compile worker executables without creating a deployment bundle.
---

Compile all worker executables from source and write them to `.zonai/executables/`. Also regenerates `.dart_tool/zonai/project_main.dart`. Does not create a deployment bundle (use `zonai build` for that).

```sh
zonai compile [flags]
```

## Flags

| Flag | Description |
|------|-------------|
| `--flavor <name>` | Config flavor to compile with — also selects `.env.<name>` |
| `--release` | Compile without Dart asserts |
| `--dart-define KEY=VALUE` | Override or add one compile-time define; repeat per key. Space-separated, not `--dart-define=KEY=VALUE` |
| `-c, --config <path>` | Path to a custom `zonai.yaml` |

There is **no `--dart-define-from-file`** — `.env` / `.env.<flavor>` is loaded
from the project root on its own. See
[Environment Variables](/configuration/environment-variables#there-is-no---dart-define-from-file).

## Workers Compiled

- `db_config` — config worker
- `db_rules` — rules worker (also linked in-process by the project binary)
- `db_operations` — operations worker (also linked in-process by the project binary)
- `db_extensions` — extensions worker
- `db_rate_limit` — rate limit worker
- `db_crons` — crons worker

## When to Use Manually

In dev mode (`zonai serve`), Zonai watches source files and recompiles workers automatically — manual `compile` is rarely needed during development. Use it for:

- Setting up a fresh clone before starting the server
- Verifying compilation succeeds in CI
- Updating compiled binaries after discarding changes that left executables stale
- Preparing workers before running `zonai rules` without starting the server

## vs. zonai build

- `zonai compile` — workers only, to `.zonai/executables/`. Use during development.
- `zonai build` — workers + **project-linked** `build/zonai` + migrations/settings. Use for deployment.
