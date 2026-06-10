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
| `--flavor <name>` | Config flavor to compile workers with |
| `--release` | Compile without Dart asserts (recommended for production) |
| `-c, --config <path>` | Path to a custom `zonai.yaml` |

## What's in build/

```
build/
├── zonai                       # Compiled Zonai CLI binary
├── .zonai/executables/         # Compiled worker binaries
├── migrations/                 # SQL migration files
├── email_templates/            # HTML email templates
└── zonai.yaml                  # Project configuration
```

Copy the entire `build/` directory to your server and run:

```sh
./zonai serve --release --flavor prod
```

## Typical Production Build

```sh
zonai build --flavor prod --release
```

## Cross-Compilation

By default, `build` targets the current machine's OS and architecture. Set `buildSettings.targetOs` and `buildSettings.targetArch` in `zonai.yaml` to cross-compile for a different target. See [Cross-Compilation](/deployment/cross-compilation).

## vs. zonai compile

- `zonai compile` — compiles workers to `.zonai/executables/` only; no bundle. Use during development.
- `zonai build` — creates the full deployable bundle. Use for deployment.
