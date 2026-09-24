# Contributing to zonai

This file is for working **on** zonai. To **use** zonai in your own project, read
<https://docs.zonai.dev> (AI agents: <https://docs.zonai.dev/llms.txt>).

## What you need

| Tool | Version | Why |
| --- | --- | --- |
| Dart SDK | **3.13.2** (the version CI and releases build with; `pubspec.yaml` allows `>=3.12.0 <4.0.0`) | Everything. A different SDK builds, but the released binary's VM snapshot hash comes from the SDK, so match CI when comparing behaviour. |
| Git | any recent | Two submodules. |
| [`sip`](https://github.com/mrgnhnt96/sip) | `main` | Runs the named scripts in `scripts.yaml`. |
| A C toolchain (Xcode CLT / build-essential / MSVC) | — | `bootstrap test` builds the native resqlite and Argon2 libraries. |

```bash
dart pub global activate --source git https://github.com/mrgnhnt96/sip.git --git-ref main
```

## First-time setup

```bash
git clone https://github.com/mrgnhnt96/zonai.git
cd zonai
git submodule update --init --recursive
./tool/setup_raindrop_submodule.sh   # sparse-checks raindrop to packages/ (Windows: .ps1)
dart pub get                          # resolves the whole pub workspace from the root
sip run bootstrap test                # generates apps/zonai/lib/gen (native libs + server tree)
```

Why each step exists:

- **`setup_raindrop_submodule.sh`**: `libs/raindrop` is a fork (`origin` =
  [mrgnhnt96/raindrop](https://github.com/mrgnhnt96/raindrop), `upstream` =
  [wolfenrain/raindrop](https://github.com/wolfenrain/raindrop)). Its root `pubspec.yaml` is a
  separate workspace, and pub rejects it as a "stray pubspec". The script checks out
  `packages/` only. Rerun it whenever pub complains about a stray pubspec near `libs/raindrop`.
- **`bootstrap test`**: `apps/zonai/lib/gen/` is gitignored, and `apps/zonai` imports from it.
  Without it, tests fail to load with `lib/gen/native/resqlite_native.g.dart: No such file`.
  Rerun it after switching branches or changing `apps/server` routes.

## Repository map

| Path | What it is |
| --- | --- |
| `apps/zonai` | The `zonai` CLI and runtime. This is the product binary users download. |
| `apps/server` | The HTTP server (revali). It is copied into `apps/zonai/lib/gen/server` at build time. |
| `apps/web` | The admin dashboard served at `/_` (Jaspr). |
| `apps/docs` | The user docs site, <https://docs.zonai.dev> (Jaspr Content). See its [README](apps/docs/README.md). |
| `apps/website` | The marketing site, <https://zonai.dev>. |
| `apps/playground` | A sample zonai project used for local runs and doc-snippet tests. |
| `apps/compat` | The fixture for the old-CLI/new-schema compatibility check. |
| `libs/zonai_schema` | Published to pub.dev. Everything a user's project imports: tables, rules, operations, config. |
| `libs/zonai_client` | Published to pub.dev. The Dart client. |
| `libs/zonai_logger` | Shared logger. |
| `libs/raindrop`, `libs/resqlite` | Submodules: the ORM/migrations and the SQLite driver. |
| `e2e/*` | Fixture projects driven through a compiled binary by `sip run test e2e`. |
| `stress/` | Load and leak harness, run weekly. See [stress/README.md](stress/README.md). |
| `tool/`, `tool/ci/` | Build, release and CI scripts. |

## Running things

| Goal | Command |
| --- | --- |
| Serve the playground from source | `sip run playground serve` (or `playground dev` for the TUI) |
| Build the full release binary into `build/zonai` | `sip run zonai compile` |
| Before pushing: analyze, format, unit tests | `sip run test` |
| CLI suite (needs `bootstrap test`) | `sip run test cli` |
| End-to-end fixtures (needs `zonai compile`) | `sip run test e2e` |
| Docs site: serve / test | `sip run docs start` / `sip run docs test` |
| Submodule suites (own native build) | `sip run test submodules` |

`scripts.yaml` is the source of truth for all of these. Each target explains its prerequisites.

## Rules that are easy to break

- **Never pass a dot-shorthand (`.get`) as an annotation argument that revali reads.** Spell out
  the type (`RateLimitOperation.get`). See
  [docs/revali-dot-shorthand-codegen.md](docs/revali-dot-shorthand-codegen.md).
- **Every ` ```dart ` fence in `docs/*.md` and `apps/docs/content/**` is analyzed** by
  `apps/playground/test/doc_snippets_test.dart`. A snippet must compile, or be spliced into a
  scaffold (` ```dart in:<name> `), or be tagged ` ```dart no-analyze ` with the reason in the
  prose. See [the scaffold README](apps/playground/test/fixtures/doc_scaffolds/README.md).
- **`sqlite3` is pinned `<3.0.0` on purpose.** Read
  [docs/sqlite3-3x-migration.md](docs/sqlite3-3x-migration.md) before lifting it.
- **Do not release while `Test` is red.** See [docs/releasing.md](docs/releasing.md).

## Documentation

- **User-facing docs go on the site** (`apps/docs/content/`). If you are explaining how to *use*
  a feature, it goes there, not in `docs/`. When you add a page, add it to
  `apps/docs/lib/src/navigation.dart` and `apps/docs/web/llms.txt`.
- **`docs/`** holds contributor material only. [docs/README.md](docs/README.md) indexes it.
