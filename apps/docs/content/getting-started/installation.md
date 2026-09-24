---
title: Installation
description: Prerequisites and how to install the Zonai CLI.
---

## Requirements

| What | Needed for | Notes |
| --- | --- | --- |
| **Dart SDK** `>=3.12.0 <4.0.0` | Development and `zonai build` | The CLI runs `dart pub get` and compiles your workers with the SDK on your `PATH`. Use the Dart version the release was built with — currently **3.13.x**. See [below](#dart-sdk-version). |
| **The `zonai` binary** | Everything | A pre-compiled executable from GitHub Releases. It is **not** on pub.dev and is not installed with `dart pub global activate`. |
| **macOS, Linux, or Windows** | — | Builds: macOS arm64 and x64, Linux x64 and arm64, Windows x64. |
| Git | Recommended | Migrations in `.zonai/migrations/` are meant to be committed. |

SQLite is bundled in the binary; there is nothing to install. The production server needs none of the above except the `build/` folder that `zonai build` produces: it runs without a Dart SDK.

## Install the CLI

Keep one `zonai` binary in the root of each project and run it from there as `./zonai`. It reads `zonai.yaml` from the current directory, and that file pins the CLI version the project uses.

**macOS and Linux** — one self-extracting file that picks your OS and architecture at run time:

```bash
curl -fsSL https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai -o zonai
chmod +x zonai
```

**Windows** — download [zonai-windows-x64.zip](https://github.com/mrgnhnt96/zonai/releases/latest/download/zonai-windows-x64.zip) and extract `zonai.exe` into the project root.

To pin a version, replace `latest/download` with `download/v<version>`, for example `https://github.com/mrgnhnt96/zonai/releases/download/v0.9.1/zonai`.

<Info>

**Per-architecture zips** are also attached to every release, if you would rather not use the self-extracting file: `zonai-macos-arm64.zip`, `zonai-macos-x64.zip`, `zonai-linux-x64.zip`, `zonai-linux-arm64.zip`. See [all releases](https://github.com/mrgnhnt96/zonai/releases).

</Info>

Check it runs:

```bash
./zonai version
# Zonai: v0.9.1
```

## Packages

You do not add anything by hand to get started. The first `./zonai dev` in an empty folder writes a `pubspec.yaml` that depends on [`zonai_schema`](https://pub.dev/packages/zonai_schema) (the API your tables, rules, and hooks are written against) and runs `dart pub get`. If the folder already has a `pubspec.yaml`, add it yourself:

```bash
dart pub add zonai_schema
```

Apps that call the server add [`zonai_client`](https://pub.dev/packages/zonai_client) to *their* `pubspec.yaml`. See [Dart Client](/dart-client/overview).

## Dart SDK version

The released binary loads worker snapshots compiled by *your* Dart SDK, so the two must share a VM snapshot format. On a mismatch the CLI prints both versions: `zonai compile` and `zonai build` refuse to run, and every other command warns. Switch to the Dart version it names. Patch releases in one minor line usually match (3.13.1 and 3.13.2 do), but not always, so trust the message over the version number.

## Updating

```bash
./zonai version check    # is a newer release out?
./zonai version update   # download it over the current binary and update `version:` in zonai.yaml
./zonai compile          # recompile workers against the new version
```

If `zonai.yaml` names a different version than the binary, any command offers to download the version the project asks for. Read [Upgrading Zonai](/cli/upgrading) before crossing a breaking release.

## Next Steps

- [Quick Start](/getting-started/quick-start) — create a project and run it
- [Project Structure](/getting-started/project-structure) — what the files are and which ones you need
