---
title: Cross-Compilation
description: Building for a different OS or architecture than your dev machine.
---

Most developers work on macOS or Apple Silicon but deploy to Linux servers. Without cross-compilation, compiled binaries only run on the machine that built them.

## Configuring buildSettings

Add `buildSettings` to `zonai.yaml`:

```yaml
buildSettings:
  targetOs: linux
  targetArch: x64
```

| Field | Values | Default |
|-------|--------|---------|
| `targetOs` | `linux`, `macos`, `windows` | Current machine OS |
| `targetArch` | `arm64`, `x64` | Current machine arch |

## How It Works

Dart supports AOT cross-compilation — `dart compile exe` produces a native binary for any supported target directly. No emulator, VM, or Docker build environment needed.

## Common Scenarios

**macOS Apple Silicon → Linux x64 (typical cloud server)**

```yaml
buildSettings:
  targetOs: linux
  targetArch: x64
```

**Any machine → Linux ARM64 (Graviton, Raspberry Pi)**

```yaml
buildSettings:
  targetOs: linux
  targetArch: arm64
```

## Building

```sh
zonai build --flavor prod --release
```

With `buildSettings` configured, the `build/` bundle contains a **project-linked**
`zonai` binary and workers for the target platform — all compiled with
`dart compile exe`, not downloaded.

## Verifying the Build

```sh
file build/zonai
# build/zonai: ELF 64-bit LSB pie executable, x86-64
```

The binary will not run on your host machine if the target OS/arch differs from the host — that's expected.
