---
title: zonai build
description: Compile a production-ready deployment bundle.
---

Create a complete, self-contained deployment bundle in the `build/` directory. No Dart SDK is required on the target machine.

```sh
zonai build [flags]
```

## Flags

| Flag | Description |
|------|-------------|
| `--flavor <name>` | Config flavor to compile with — also selects `.env.<name>` |
| `--release` | Compile without Dart asserts (recommended for production) |
| `--dart-define KEY=VALUE` | Override or add one compile-time define; repeat per key. Space-separated, not `--dart-define=KEY=VALUE` |
| `-c, --config <path>` | Path to a custom `zonai.yaml` |

There is **no `--dart-define-from-file`** and none is needed: `.env` (or
`.env.<flavor>`) is read from the project root automatically and compiled in.
An unrecognized flag is silently ignored rather than rejected, so a wrong flag
name builds cleanly with the defines missing. See
[Environment Variables](/configuration/environment-variables#there-is-no---dart-define-from-file).

## What's in build/

```
build/
├── zonai                       # Project-linked binary (ops/rules + full CLI)
├── .zonai/executables/         # Worker binaries (config, extensions, …)
├── migrations/                 # SQL migration files
├── email_templates/            # HTML email templates
└── zonai.yaml                  # Project configuration
```

`build/zonai` is compiled from your project's generated entry
(`.dart_tool/zonai/project_main.dart`). It embeds your schemas, operations,
and rules **in-process**, and still exposes `serve`, `db`, `compile`, and the
rest of the CLI. It is **not** a copy of the global/bootstrap `zonai` tool.

Copy the entire `build/` directory to your server and run:

```sh
./zonai serve --release --flavor prod
```

## Typical Production Build

```sh
zonai build --flavor prod --release
```

## Cross-Compilation

By default, `build` targets the current machine's OS and architecture. Set `buildSettings.targetOs` and `buildSettings.targetArch` in `zonai.yaml` to cross-compile the project binary and workers for a different target. See [Cross-Compilation](/deployment/cross-compilation).

## vs. zonai compile

- `zonai compile` — compiles workers to `.zonai/executables/` only; no bundle. Use during development.
- `zonai build` — workers + project-linked `build/zonai` + migrations/settings. Use for deployment.
