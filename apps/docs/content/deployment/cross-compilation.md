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

`dart compile exe --target-os/--target-arch` produces native binaries for the target directly — no emulator, VM, or Docker build environment needed. Dart only cross-compiles **to Linux**: any `linux` target works from any host, but a `macos` or `windows` target must match the machine you build on (OS and architecture), or `zonai build` fails with `Cannot build for …`.

When the target differs from the host, `zonai build` also downloads the target's native libraries into `build/.zonai/lib/`, so the bundle does not carry your build machine's copies.

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

With `buildSettings` configured, every binary in `build/` — the `zonai` server
and all workers — is built for the target platform. See
[Building for Production](/deployment/building-for-production#what-gets-bundled)
for what `build/zonai` is.

## Verifying the Build

```sh
file build/zonai
# build/zonai: ELF 64-bit LSB pie executable, x86-64
```

The binary will not run on your host machine if the target OS/arch differs from the host — that's expected.
