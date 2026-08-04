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
- [Linux (arm64)](https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai-linux-arm64.zip)
- [Windows (x64)](https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai-windows-x64.zip)

Extract the zip and place the `zonai` (or `zonai.exe`) binary in the root of your project.

On macOS or Linux you can skip picking an architecture: [`zonai`](https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai) is a single self-extracting file (~35 MiB) that detects the current OS/arch and dispatches to the matching binary embedded inside it (macOS arm64, macOS x64, Linux x64, Linux arm64 — all four, picked at runtime). Download it, `chmod +x zonai`, and run it directly — no zip, no picking a platform, no other tools required. The first run decompresses and caches the binary for your platform using a small decompressor bundled inside the file itself; later runs skip straight to it. It isn't a Windows-runnable `.exe`; Windows always needs the dedicated `zonai-windows-x64.zip` above.

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
- **Disk** — worker binaries live in `.zonai/executables/`; a project-linked `build/zonai` from `zonai build` is typically tens of MB
- No runtime dependencies on the production server — the compiled bundle is self-contained

## Next Steps

- [Quick Start](/getting-started/quick-start) — build and run your first project (includes a live **stream** example)
- [Live Queries (Streaming)](/operations/streaming) — `/db/stream*` and `client.db.listen` (do not poll)
- [Dart Client](/dart-client/overview) — prefer `zonai_client` over hand-rolled HTTP
