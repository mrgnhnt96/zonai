# Release mode

Zonai’s **`--release`** flag switches between development and production behavior. Pass it to **`build`** or **`compile`** when building, and to **`serve`** when running on a server.

For shipping to a server or container, use **`zonai build`** to assemble everything under `build/` (workers, migrations, settings, and a **project-linked** `zonai` binary). Use **`compile`** only when you need workers under `.zonai/executables/` without creating a deploy bundle.

In development (default), workers are compiled with **`--enable-asserts`**, so `assert(...)` checks in your config, rules, extensions, operations, and rate-limit Dart code stay active. `serve` also enables file watchers, keyboard shortcuts, and auto-migration generation. Ops/rules run **in-process** via the generated project entry.

## Enable release mode

Pass **`--release`** to **`serve`** or **`compile`** from your app directory (where `zonai.yaml` lives):

```bash
# Prepare deployable assets under build/
dart run zonai build --release

# Build workers for local serve only (no build/ bundle)
dart run zonai compile --release

# Serve on a server using the project binary / pre-built workers
./zonai serve --release   # from build/
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
| `assert(...)` in compiled code | evaluated at runtime | stripped / not evaluated |
| File watchers (workers) | on during `serve` | off during `serve` |
| Keyboard shortcuts during `serve` | on (`c`, `m`, `p`, `q`, `r`) | off |
| Auto-migration watcher during `serve` | on | off |
| Migration generation during `serve` | on | off |
| Typical use | local dev, debugging | servers, CI build artifacts |

## `build` vs `compile`

| | **`compile`** | **`build`** |
| --- | --- | --- |
| Worker output | `.zonai/executables/*.exe` | `build/.zonai/executables/*.exe` |
| Migrations | not copied | SQL files copied into `build/` |
| Settings file | not copied | `zonai.yaml` / `zonai.yml` copied into `build/` |
| Project binary | not built (entry regenerated) | `build/zonai` — project-linked ops/rules + full CLI |
| Typical use | local workers, quick rebuilds | CI, deploy hosts, containers |

`build` wipes the existing `build/` directory, compiles all workers (honoring `--release` and `--flavor`), copies migration SQL, copies your settings file, then **compiles** a project-linked `zonai` executable into `build/`. Ship the whole `build/` directory and run `./zonai serve --release` from there (see **[server-binding.md](server-binding.md)** for host/port from the copied settings file).

Cross-compile to another OS or architecture with **`buildSettings`** in `zonai.yaml`:

```yaml
buildSettings:
  targetOs: linux
  targetArch: x64
```

Defaults match the machine running `build`. The target must be compatible with your host (for example, you cannot cross-compile to macOS from Apple Silicon). Both the **project binary** and **workers** are produced with `dart compile exe` using those targets — there is no separate download of a generic CLI binary.

### Which workers are affected

Workers use the same compile flags:

| Worker | Output executable |
| --- | --- |
| Config | `.zonai/executables/db_config.exe` |
| Rules | `.zonai/executables/db_rules.exe` |
| Operations | `.zonai/executables/db_operations.exe` |
| Extensions | `.zonai/executables/db_extensions.exe` |
| Rate limits | `.zonai/executables/db_rate_limit.exe` |
| Crons | `.zonai/executables/db_crons.exe` |

Ops/rules are **also** linked into `build/zonai` for in-process dispatch. Set `ZONAI_FORCE_WORKERS=1` to use the Mailman `.exe` path for ops/rules instead.

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

- Both commands build workers once with or without asserts according to `--release`.
- Prefer **`build --release`** for deploy artifacts (full `build/` bundle with project binary).
- Use **`compile --release`** when you only need `.zonai/executables/` in-tree.

**`serve --release`**

- Does **not** watch worker source directories for changes.
- Does **not** recompile on startup, on file changes, or via keyboard shortcuts.
- Does **not** enable keyboard shortcuts, terminal input handling, auto-migration watching, or migration generation.
- Expects a project-linked binary (from `build`) and/or pre-built workers.

If workers required at runtime are missing when you start `serve --release`, the server logs an error pointing you to `zonai compile --release` or `zonai build --release`.

## Recommended workflows

### Local development

```bash
dart run zonai serve --flavor dev
```

The CLI re-execs into the JIT project entry (ops/rules in-process). File watchers recompile **workers** when you edit config, extensions, rate limits, or crons. Press **`c`** to recompile everything, **`m`** to generate migrations, **`p`** to ping workers, and **`q`** to quit. Restart serve after editing ops/rules so the linked entry reloads.

### Production build (CI or deploy host)

```bash
cd apps/my-app
dart run zonai build --flavor prod --release
```

Ship the `build/` directory (project-linked `zonai`, workers under `build/.zonai/executables/`, migration SQL, copied `zonai.yaml`). Env secrets selected at build time are embedded in the compiled binaries.

Migration SQL should already exist in your repo from development. `build --release` copies those files into `build/`; no separate migration step is required before deploy. When `serve --release` starts, pending migrations are applied automatically when the database opens. Release mode only disables **generating** migrations during serve (auto-migrate watcher, **`m`**, and `migrate run` with `--release`).

### Production serve

From a **`build/`** output directory:

```bash
cd build
./zonai serve --release
```

Use the same `--flavor` you used when building. To update linked ops/rules or env defines, run `build --release` again and redeploy.

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
- Rely on file watchers and **`c`** to recompile workers after edits; restart serve after ops/rules edits.
- Use **`m`** or the auto-migration watcher to generate migrations from schema changes.
- Use `--flavor dev` and `.env.dev` as needed.

**Production**

- Run **`build --release`** (with the correct `--flavor`) before deploy, and ship the `build/` directory.
- Run **`serve --release`** from `build/` via `./zonai`.
- Use **`--flavor prod`** (or your production flavor) and the matching env file at build time.
- Treat compiled binaries as containing compile-time secrets.
- Re-run `build --release` after changing source or env defines.
- Commit migration SQL from development when schemas change; `build` bundles it and `serve --release` applies pending migrations at startup.

## See also

- **[config-and-env-flavors.md](config-and-env-flavors.md)** — `--flavor`, env files, and compile-time defines
- **[operations.md](operations.md)**, **[rules.md](rules.md)**, **[extensions.md](extensions.md)**, **[rate-limiting.md](rate-limiting.md)** — source layout and compile flow
