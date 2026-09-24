---
title: Project Structure
description: What every directory and file in a Zonai project does.
---

This is a project right after `./zonai dev` initializes it, with one table added:

```
my_app/
├── zonai                       # The CLI binary (zonai.exe on Windows)
├── zonai.yaml                  # Required. Its presence marks the project root
├── pubspec.yaml                # Required. Depends on zonai_schema
├── .env                        # Optional. Compile-time secrets (gitignore it)
├── lib/src/
│   ├── ids.dart                # One ID type per table
│   ├── schemas/                # Required. Table definitions
│   │   ├── admins.dart         #   scaffolded admin auth table
│   │   └── tasks.dart
│   ├── config/db_config.dart   # Required. AppConfig: secrets, baseUrl, SMTP
│   ├── rules/                  # Required per table. Authorization
│   ├── operations/             # Optional. Custom SQL
│   ├── extensions/             # Optional. Lifecycle hooks
│   ├── rate_limit/             # Optional. Per-table throttling
│   ├── crons/                  # Optional. Scheduled jobs
│   └── email_templates/        # Mustache HTML templates (built-ins scaffolded)
├── .zonai/
│   ├── migrations/             # Generated SQL. Commit these
│   ├── executables/            # Compiled workers (generated)
│   └── data/                   # SQLite database and uploaded images
└── build/                      # Only after `zonai build`. The deployable bundle
```

## What is required

| Path | Required? | Created by `zonai dev` init? |
| --- | --- | --- |
| `zonai.yaml` | **Yes.** Without it, `dev` and `serve` offer to initialize the folder | Yes |
| `pubspec.yaml` with `zonai_schema` | **Yes** | Yes, unless a `pubspec.yaml` already exists; then add `zonai_schema` yourself |
| `lib/src/config/` with an `AppConfig main()` | **Yes.** The server will not start without valid secrets | Yes, with random 48-byte secrets |
| `lib/src/schemas/` | **Yes**, one or more tables | Yes (`admins`) |
| Rules for each table | **Yes**. Without them, every request to that table gets `403` | For `admins` only |
| `.zonai/migrations/` | **Yes**, once you have tables | The directory only. See [Generating Migrations](/database/generating-migrations) |
| Everything else | No | `extensions/`, `rate_limit/`, and `crons/` are created empty |

Every path in `zonai.yaml` is optional and falls back to the layout above. See the [zonai.yaml Reference](/configuration/zonai-yaml). The file's `version:` pins the CLI release the project uses.

## Source directories (`lib/src/`)

Every `.dart` file in these directories is picked up automatically. There is no registration step. Each file **except schemas** must have a top-level `main()` that returns its object, such as `TaskTableRules main() => TaskTableRules();`. A file without one fails to load.

**`schemas/`** declares tables. Each file defines a row type and a table class, then registers it with `table(...)` or `authTable(...)`. See [Defining Tables](/schemas/defining-tables).

**`config/`** returns an `AppConfig`: the app name, JWT and password secrets, `baseUrl`, SMTP, and more. `JWT_SECRET` and `PASSWORD_SECRET` in the server's environment override the compiled-in values at startup. See [App Config](/configuration/app-config).

**`rules/`** holds authorization. A table needs a **table rules** class (`TableRules` or `AuthTableRules`) and a **row rules** class (`RowRules` or `AuthRowRules`), one per file. Methods you do not override allow admins and deny everyone else. See [Rules Overview](/rules/overview).

**`operations/`** holds custom SQL, extra JWT claims, and custom operations. Default CRUD and live-stream operations already exist for every table, so this directory is optional.

**`extensions/`** holds before/after hooks on mutations and auth events, for side effects like email, related rows, or audit logs.

**`rate_limit/`** holds per-table throttle policies. Tables without one get the default policy.

**`crons/`** holds `CronJob` subclasses run on a cron schedule.

**`email_templates/`** holds HTML with Mustache variables. Init writes the built-in templates here so you can edit them.

### Naming conventions

File names are conventions, not requirements. They keep one class per file easy to find:

| Type | File name | Example |
|------|-----------|---------|
| Table rules | `<table>_table_rules.dart` | `task_table_rules.dart` |
| Row rules | `<table>_row_rules.dart` | `task_row_rules.dart` |
| Operations | `<table>_operations.dart` | `task_operations.dart` |
| Extensions | `<table>_extensions.dart` | `task_extensions.dart` |
| Rate limits | `<table>_rate_limits.dart` | `task_rate_limits.dart` |

Pressing `f` (create part) in the `zonai dev` TUI writes any of these from a template.

## Generated files

Zonai manages these. Don't edit them by hand.

- **`.zonai/migrations/`**: SQL written by `zonai db migrate generate`. This is your schema history, so **commit it**.
- **`.zonai/executables/`**: compiled workers, rebuilt by `zonai compile` and by `dev`/`serve`.
- **`.zonai/data/`**: the SQLite database and uploaded images. Never commit it.
- **`.zonai/zonai`**: a compiled project binary, created only for projects that link Zonai into their own server.
- **`.dart_tool/zonai/`**: generated worker entrypoints.
- **`build/`**: created by `zonai build`. It holds the server binary, workers, migrations, email templates, and `zonai.yaml`. Ship the whole folder. See [Building for Production](/deployment/building-for-production).

## What to commit

Init adds only `*.stop`, `zonai.sqlite*`, `.serve.lock`, and `pubspec_overrides.yaml` to `.gitignore`. Add the rest yourself:

```text
.dart_tool/
.zonai/executables/
.zonai/data/
.zonai/zonai
build/
.env
.env.*
```

Commit `lib/`, `zonai.yaml`, `pubspec.yaml`, `pubspec.lock`, and `.zonai/migrations/`. Whether to commit the `zonai` binary is up to you. `zonai.yaml` already records its version, and any command offers to download that version when the binary differs.
