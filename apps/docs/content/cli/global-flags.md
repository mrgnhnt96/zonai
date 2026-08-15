---
title: Global Flags
description: Flags available on all Zonai CLI commands.
---

These flags are accepted by all Zonai commands.

## Flags

| Flag | Short | Description |
|------|-------|-------------|
| `--help` | `-h` | Print usage information for the current command |
| `--config <path>` | `-c` | Path to `zonai.yaml`; auto-detected if omitted |
| `--flavor <name>` | — | Config flavor to load (affects `serve`, `compile`, `build`) |
| `--release` | — | Production mode: disable asserts, disable file watchers in `serve` |
| `--quiet` | `-q` | Suppress all non-error output |
| `--loud` | `-L` | Maximum verbosity — print all internal debug logs |
| `--log <level>` | — | Set log level: `verbose`, `trace`, `request`, `debug`, `info`, `warning`, `error` (or their first letter: `v t r d i w e`) |

The level names are matched exactly. `--log warn` is **not** `warning`: an
unrecognized name is ignored and the level falls back to `info`.

## Unrecognized Flags Are Ignored

Zonai parses arguments generically — every `--flag value` pair is collected,
and commands read the keys they know. A flag no command reads is **not an
error**: it is dropped without a warning and the command succeeds.

```sh
zonai build --dart-define-from-file env.json   # exits 0, injects nothing
```

Nothing reads `--dart-define-from-file` (it doesn't exist — see
[Environment Variables](/configuration/environment-variables#there-is-no---dart-define-from-file)),
so that build silently ships without those values. When a flag appears to have
had no effect, check its spelling against the command's `--help` first.

## --config Auto-Detection

If `--config` is not provided, Zonai searches the current directory and its parents for `zonai.yaml` or `zonai.yml`. The first file found is used. This allows running commands from any subdirectory of the project.

## --flavor and --release

These flags are independent:

- `--flavor` selects which config file is compiled into workers
- `--release` controls compilation flags (no asserts) and `serve` behavior (no watchers)

You can combine them freely:
```sh
zonai serve --flavor dev --release   # release build of dev config
zonai build --flavor prod --release  # production build
```
