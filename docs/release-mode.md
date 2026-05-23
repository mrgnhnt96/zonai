# Release mode

Zonai’s **`--release`** flag tells the CLI to compile worker executables for production: without Dart’s `--enable-asserts` flag. Use it when serving on a server or when building workers in CI before deploy.

In the default (development) mode, every worker is compiled with **`--enable-asserts`**, so `assert(...)` checks in your config, rules, extensions, operations, and rate-limit Dart code stay active inside the running `.exe` files.

## Enable release mode

Pass **`--release`** to **`serve`** or **`compile`** from your app directory (where `zonai.yaml` lives):

```bash
# Build all workers for production
dart run zonai compile --release

# Serve with production worker builds
dart run zonai serve --release
```

Combine with **`--flavor`** when you use flavored configs and env files:

```bash
dart run zonai compile --flavor prod --release
dart run zonai serve --flavor prod --release
```

Release mode is **off by default**. Omitting `--release` keeps development behavior (asserts enabled in workers).

## What changes

| | Development (default) | Release (`--release`) |
| --- | --- | --- |
| Worker compile flag | `--enable-asserts` | omitted |
| `assert(...)` in worker code | evaluated at runtime | stripped / not evaluated |
| Typical use | local dev, debugging | servers, CI build artifacts |

Release mode only affects how **worker executables** are built. It does not change how the Zonai CLI itself is run (`dart run zonai` vs a compiled zonai binary).

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

- **`compile`** — all workers are built once with or without asserts according to `--release`.
- **`serve`** — workers are compiled on startup (and when you press **`c`** to recompile, or when watched source files change) using the same `--release` setting you passed to `serve`.

If you start `serve` without `--release` and later need production binaries, run `compile --release` or restart `serve` with `--release` so workers are rebuilt.

## Recommended workflows

### Local development

```bash
dart run zonai serve --flavor dev
```

Workers include asserts. File watchers recompile workers when you edit config, rules, extensions, operations, or rate limits.

### Production build (CI or deploy host)

```bash
cd apps/my-app
dart run zonai compile --flavor prod --release
```

Commit or ship the resulting `.zonai/executables/*.exe` artifacts along with your app. Env secrets selected at compile time are embedded in those binaries.

### Production serve

```bash
dart run zonai serve --flavor prod --release
```

Use the same `--flavor` and `--release` flags you used when compiling, so startup recompiles (if any) match your deploy intent.

## Not the same as other “release” concepts

| Name | Meaning |
| --- | --- |
| **`zonai serve --release`** | Production worker builds (this document) |
| **`kIsCompiled`** (`__ZONAI_COMPILED__`) | Zonai CLI or server running as a compiled executable instead of `dart run` |
| **Jaspr `--release`** (web app) | Optimized client/server build for `apps/web`; unrelated to Zonai worker flags |

## Development vs production checklist

**Development**

- Omit `--release` (asserts on in workers).
- Rely on file watchers and **`c`** to recompile after edits.
- Use `--flavor dev` and `.env.dev` as needed.

**Production**

- Pass **`--release`** to `compile` and `serve`.
- Use **`--flavor prod`** (or your production flavor) and the matching env file.
- Treat `.zonai/executables/*.exe` as containing compile-time secrets.
- Re-run `compile --release` after changing worker source or env defines.

## See also

- **[config-and-env-flavors.md](config-and-env-flavors.md)** — `--flavor`, env files, and compile-time defines
- **[operations.md](operations.md)**, **[rules.md](rules.md)**, **[extensions.md](extensions.md)**, **[rate-limiting.md](rate-limiting.md)** — worker source layout and compile flow
