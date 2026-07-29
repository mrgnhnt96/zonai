# Release mode

Zonai’s **`--release`** flag switches between development and production behavior. Pass it to **`build`** or **`compile`** when building worker executables, and to **`serve`** when running on a server.

For shipping to a server or container, use **`zonai build`** to assemble everything under `build/` (workers, migrations, settings, and a `zonai` binary). Use **`compile`** only when you need workers under `.zonai/executables/` for local `serve` without creating a deploy bundle.

In development (default), workers are compiled with **`--enable-asserts`**, so `assert(...)` checks in your config, rules, extensions, operations, and rate-limit Dart code stay active inside the running `.exe` files. `serve` also enables file watchers, keyboard shortcuts, and auto-migration generation.

## Enable release mode

Pass **`--release`** to **`serve`** or **`compile`** from your app directory (where `zonai.yaml` lives):

```bash
# Prepare deployable assets under build/
dart run zonai build --release

# Build workers for local serve only (no build/ bundle)
dart run zonai compile --release

# Serve on a server using pre-built workers
dart run zonai serve --release
```

Combine with **`--flavor`** when you use flavored configs and env files:

```bash
dart run zonai build --flavor prod --release
dart run zonai compile --flavor prod --release
dart run zonai serve --flavor prod --release
```

Release mode is **off by default**. Omitting `--release` keeps development behavior.

## What changes

| | Development (default) | Release (`--release`) |
| --- | --- | --- |
| Worker compile flag | `--enable-asserts` | omitted |
| `assert(...)` in worker code | evaluated at runtime | stripped / not evaluated |
| File watchers (workers) | on during `serve` | off during `serve` |
| Keyboard shortcuts during `serve` | on (`c`, `m`, `p`, `q`, `r`) | off |
| Auto-migration watcher during `serve` | on | off |
| Migration generation during `serve` | on | off |
| Typical use | local dev, debugging | servers, CI build artifacts |

Release mode does not change how the Zonai CLI itself is run (`dart run zonai` vs a compiled zonai binary).

## `build` vs `compile`

| | **`compile`** | **`build`** |
| --- | --- | --- |
| Worker output | `.zonai/executables/*.exe` | `build/.zonai/executables/*.exe` |
| Migrations | not copied | SQL files copied into `build/` |
| Settings file | not copied | `zonai.yaml` / `zonai.yml` copied into `build/` |
| Zonai CLI binary | not included | `build/zonai` (or `zonai.exe` on Windows) for the target platform |
| Typical use | local `serve`, quick worker rebuilds | CI, deploy hosts, containers |

`build` wipes the existing `build/` directory, compiles all workers (honoring `--release` and `--flavor`), copies migration SQL, copies your settings file, then places a `zonai` executable in `build/`. Ship the whole `build/` directory and run `./zonai serve --release` from there (see **[server-binding.md](server-binding.md)** for host/port from the copied settings file).

Cross-compile to another OS or architecture with **`buildSettings`** in `zonai.yaml`:

```yaml
buildSettings:
  targetOs: linux
  targetArch: x64
```

Defaults match the machine running `build`. The target must be compatible with your host (for example, you cannot cross-compile to macOS from Apple Silicon).

**This only affects the worker executables** (config, rules, operations, extensions, rate limits) — those are compiled locally on every `build`, subject to the same-host restriction above. The **`zonai` binary bundled into `build/`** works differently depending on whether `buildSettings` targets the machine running `build`:

- **Same platform** (the default): `build` copies the already-running `zonai` binary straight into `build/zonai` — nothing is downloaded, no network access needed. This only applies when running a *compiled* `zonai` (not `dart run zonai build`, which has no running binary to copy from).
- **Different platform** (`buildSettings` targets another OS/arch, or you ran `dart run zonai build`): `build` downloads the matching release binary from `mrgnhnt96/zonai`'s GitHub releases for `zonai.yaml`'s `version`. That release tag and a matching asset (`zonai-linux-x64.zip`, `zonai-windows-x64.zip`, `zonai-macos-arm64.zip`, or `zonai-macos-x64.zip`) must already exist, and the machine running `build` needs network access to `api.github.com`. If this repository is private, set **`GITHUB_TOKEN`** or **`GH_TOKEN`** in the environment first — an unauthenticated request against a private repo fails with a 404, not a clear permissions error.

### Which workers are affected

All five workers use the same compile flags:

| Worker | Output executable |
| --- | --- |
| Config | `.zonai/executables/db_config.exe` |
| Rules | `.zonai/executables/db_rules.exe` |
| Operations | `.zonai/executables/db_operations.exe` |
| Extensions | `.zonai/executables/db_extensions.exe` |
| Rate limits | `.zonai/executables/db_rate_limit.exe` |

Each compile step runs roughly:

```bash
# Development (default)
dart compile exe -DKEY=value ... --enable-asserts <generated-entry.dart> -o .zonai/executables/<worker>.exe

# Release (--release)
dart compile exe -DKEY=value ... <generated-entry.dart> -o .zonai/executables/<worker>.exe
```

Env defines from `.env` / `.env.<flavor>` are passed the same way in both modes. See **[config-and-env-flavors.md](config-and-env-flavors.md)** for flavor and env details.

### When the flag applies

**`build --release`** / **`compile --release`**

- Both commands build all workers once with or without asserts according to `--release`.
- Prefer **`build --release`** for deploy artifacts (full `build/` bundle).
- Use **`compile --release`** when you only need `.zonai/executables/` for `serve --release` in the same tree.

**`serve --release`**

- Does **not** watch worker source directories for changes.
- Does **not** recompile workers on startup, on file changes, or via keyboard shortcuts.
- Does **not** enable keyboard shortcuts, terminal input handling, auto-migration watching, or migration generation.
- Expects pre-built executables under `.zonai/executables/` from a prior `compile --release` run.

If workers are missing when you start `serve --release`, the server logs an error pointing you to `zonai compile --release` or `zonai build --release`.

## Recommended workflows

### Local development

```bash
dart run zonai serve --flavor dev
```

Workers include asserts. File watchers recompile workers when you edit config, rules, extensions, operations, or rate limits. Press **`c`** to recompile everything, **`m`** to generate migrations, **`p`** to ping workers, and **`q`** to quit.

### Production build (CI or deploy host)

```bash
cd apps/my-app
dart run zonai build --flavor prod --release
```

Ship the `build/` directory (workers under `build/.zonai/executables/`, migration SQL, copied `zonai.yaml`, and the `zonai` binary). Env secrets selected at build time are embedded in the worker executables.

Migration SQL should already exist in your repo from development. `build --release` copies those files into `build/`; no separate migration step is required before deploy. When `serve --release` starts, pending migrations are applied automatically when the database opens. Release mode only disables **generating** migrations during serve (auto-migrate watcher, **`m`**, and `migrate run` with `--release`).

If you are not using `build`, you can still run `dart run zonai compile --flavor prod --release` and ship `.zonai/executables/*.exe` with your app source tree; `serve --release` expects those paths relative to the working directory.

### Production serve

From a **`build/`** output directory:

```bash
cd build
./zonai serve --release
```

Or from the app root when workers were compiled in place:

```bash
dart run zonai serve --flavor prod --release
```

Use the same `--flavor` you used when building or compiling. Workers must already exist (under `build/.zonai/executables/` or `.zonai/executables/`). To update workers or env defines, run `build --release` (or `compile --release`) again and redeploy.

The process still responds to **`SIGTERM`** / **`SIGINT`** for graceful shutdown; only interactive keyboard controls are disabled.

## Not the same as other “release” concepts

| Name | Meaning |
| --- | --- |
| **`zonai serve --release`** | Production serve mode (this document) |
| **`zonai build --release`** | Production deploy bundle under `build/` |
| **`zonai compile --release`** | Production worker builds without asserts (in-tree `.zonai/executables/`) |
| **`kIsCompiled`** (`__ZONAI_COMPILED__`) | Zonai CLI or server running as a compiled executable instead of `dart run` |
| **Jaspr `--release`** (web app) | Optimized client/server build for `apps/web`; unrelated to Zonai worker flags |

## Development vs production checklist

**Development**

- Omit `--release` (asserts on in workers).
- Rely on file watchers and **`c`** to recompile after edits.
- Use **`m`** or the auto-migration watcher to generate migrations from schema changes.
- Use `--flavor dev` and `.env.dev` as needed.

**Production**

- Run **`build --release`** (with the correct `--flavor`) before deploy, and ship the `build/` directory.
- Run **`serve --release`** from `build/` (via `./zonai`) or from the app root with pre-built `.zonai/executables/*.exe`.
- Use **`--flavor prod`** (or your production flavor) and the matching env file at build/compile time.
- Treat worker executables as containing compile-time secrets.
- Re-run `build --release` (or `compile --release`) after changing worker source or env defines.
- Commit migration SQL from development when schemas change; `build` bundles it and `serve --release` applies pending migrations at startup.

## See also

- **[config-and-env-flavors.md](config-and-env-flavors.md)** — `--flavor`, env files, and compile-time defines
- **[operations.md](operations.md)**, **[rules.md](rules.md)**, **[extensions.md](extensions.md)**, **[rate-limiting.md](rate-limiting.md)** — worker source layout and compile flow
