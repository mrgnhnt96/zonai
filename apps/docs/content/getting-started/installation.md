---
title: Installation
description: Prerequisites and how to install the Zonai CLI.
---

## Prerequisites

**Git** is needed for version-controlling migration files (strongly recommended).

**SQLite** is bundled with Zonai — no separate installation needed.

## Installing the CLI

The `zonai` binary runs from within your project — it resolves files relative to its own location and must be placed in the project root.

Download a pre-compiled binary for your platform:

- [macOS (Apple Silicon)](https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai-macos-arm64.zip)
- [macOS (Intel)](https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai-macos-x64.zip)
- [Linux (x64)](https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai-linux-x64.zip)
- [Windows (x64)](https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai-windows-x64.zip)

Extract the zip and place the `zonai` (or `zonai.exe`) binary in the root of your project.

Verify the installation:

```bash
./zonai version
# Zonai: v0.1.0
```

## Updating the CLI

Once installed, use the CLI itself to update in place — it downloads and replaces the binary at its current location:

```bash
# Check if a newer version is available
./zonai version check

# Download and install the latest release
./zonai version update
```

After updating, recompile your workers — new versions may include worker API changes:

```bash
./zonai compile
```

## System Requirements

- **macOS, Linux, Windows** — all supported
- **Disk** — compiled worker binaries live in `.zonai/executables/` (typically 5–20 MB total per project)
- No runtime dependencies on the production server — the compiled bundle is self-contained

## Next Steps

- [Quick Start](/getting-started/quick-start) — build and run your first project
