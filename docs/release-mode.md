# Release mode

Zonai’s **`--release`** flag switches between development and production behavior. Pass it to **`compile`** when building worker executables for deploy, and to **`serve`** when running on a server.

In development (default), workers are compiled with **`--enable-asserts`**, so `assert(...)` checks in your config, rules, extensions, operations, and rate-limit Dart code stay active inside the running `.exe` files. `serve` also enables file watchers, keyboard shortcuts, and auto-migration generation.

## Enable release mode

Pass **`--release`** to **`serve`** or **`compile`** from your app directory (where `zonai.yaml` lives):

```bash
# Build all workers for production
dart run zonai compile --release

# Serve on a server using pre-built workers
dart run zonai serve --release
```

Combine with **`--flavor`** when you use flavored configs and env files:

```bash
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

**`compile --release`**

- Builds all workers once with or without asserts according to `--release`.
- Use this in CI or on a deploy host before shipping artifacts.

**`serve --release`**

- Does **not** watch worker source directories for changes.
- Does **not** recompile workers on startup, on file changes, or via keyboard shortcuts.
- Does **not** enable keyboard shortcuts, terminal input handling, auto-migration watching, or migration generation.
- Expects pre-built executables under `.zonai/executables/` from a prior `compile --release` run.

If workers are missing when you start `serve --release`, the server logs an error pointing you to `zonai compile --release`.

## Recommended workflows

### Local development

```bash
dart run zonai serve --flavor dev
```

Workers include asserts. File watchers recompile workers when you edit config, rules, extensions, operations, or rate limits. Press **`c`** to recompile everything, **`m`** to generate migrations, **`p`** to ping workers, and **`q`** to quit.

### Production build (CI or deploy host)

```bash
cd apps/my-app
dart run zonai compile --flavor prod --release
```

Commit or ship the resulting `.zonai/executables/*.exe` artifacts along with your app. Env secrets selected at compile time are embedded in those binaries.

Generate and apply database migrations separately before deploy (for example with `zonai db migrate generate` during development or CI). Release mode does not generate migrations while serving.

### Production serve

```bash
dart run zonai serve --flavor prod --release
```

Use the same `--flavor` you used when compiling. Workers must already exist under `.zonai/executables/`. To update workers or env defines, run `compile --release` again and redeploy the artifacts.

The process still responds to **`SIGTERM`** / **`SIGINT`** for graceful shutdown; only interactive keyboard controls are disabled.

## Not the same as other “release” concepts

| Name | Meaning |
| --- | --- |
| **`zonai serve --release`** | Production serve mode (this document) |
| **`zonai compile --release`** | Production worker builds without asserts |
| **`kIsCompiled`** (`__ZONAI_COMPILED__`) | Zonai CLI or server running as a compiled executable instead of `dart run` |
| **Jaspr `--release`** (web app) | Optimized client/server build for `apps/web`; unrelated to Zonai worker flags |

## Development vs production checklist

**Development**

- Omit `--release` (asserts on in workers).
- Rely on file watchers and **`c`** to recompile after edits.
- Use **`m`** or the auto-migration watcher to generate migrations from schema changes.
- Use `--flavor dev` and `.env.dev` as needed.

**Production**

- Run **`compile --release`** (with the correct `--flavor`) before deploy.
- Run **`serve --release`** with pre-built `.zonai/executables/*.exe` artifacts.
- Use **`--flavor prod`** (or your production flavor) and the matching env file at compile time.
- Treat `.zonai/executables/*.exe` as containing compile-time secrets.
- Re-run `compile --release` after changing worker source or env defines.
- Generate migrations in development or CI; do not rely on `serve --release` to create them.

## See also

- **[config-and-env-flavors.md](config-and-env-flavors.md)** — `--flavor`, env files, and compile-time defines
- **[operations.md](operations.md)**, **[rules.md](rules.md)**, **[extensions.md](extensions.md)**, **[rate-limiting.md](rate-limiting.md)** — worker source layout and compile flow
