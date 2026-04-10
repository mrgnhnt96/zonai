# Raindrop migrations in Zonai

This document describes how schema changes flow from Dart definitions into SQL, how generated artifacts are laid out, and how the app applies migrations at runtime. The `zonai_db` package (`apps/db`) uses **Raindrop** with the **SQLite** dialect and the **raindrop_cli** code generator.

## Concepts

| Piece | Role |
|--------|------|
| **Schema** | Dart classes under `lib/schemas/` that describe tables (via `sqliteTable`, `Schema`, columns). This is the source of truth you edit by hand. |
| **`raindrop_cli`** | Compares the current schema to the last snapshot, emits SQL for the diff, and updates `migrations/meta/`. |
| **`migrations/*.sql`** | Versioned SQL files (e.g. `0000_initial.sql`) checked into the repo. **These are what the app loads at runtime.** |
| **`migrations/meta/`** | Journal and snapshots the CLI uses to compute the next diff. Commit this with the SQL. |
| **`loadMigrationsFromDirectory`** | Reads `*.sql` from a directory, builds `List<Migration>` for `migrate()`. |
| **`migrate()`** | Raindrop API that runs pending migrations in order, records them in `_raindrop_migrations`, and verifies checksums. |

Runtime tracking uses a table named `_raindrop_migrations` inside your SQLite file (created automatically).

## Configuration

`apps/db/raindrop.yaml` tells the CLI where schemas live and where SQL is written. Paths are relative to the directory that contains `raindrop.yaml`.

```yaml
dialect: sqlite
schemas: lib/schemas
out: migrations
```

- **`dialect`** — Must match the package you depend on (`raindrop_sqlite` for SQLite).
- **`schemas`** — Directory of `.dart` files the analyzer walks for `sqliteTable` / table definitions.
- **`out`** — Folder for `.sql` files and the `meta/` subdirectory.

**Optional `dart:`** — If you set `dart: lib/database/migrations.dart`, `raindrop generate` will also emit a Dart file embedding every migration as const strings. Zonai does **not** use that: migrations are loaded from disk instead (see below).

The CLI accepts `-c` / `--config` to point at a config file; from `apps/db` the default `raindrop.yaml` in the current directory is used.

## Dev dependency

`apps/db/pubspec.yaml` includes **raindrop_cli** as a `dev_dependency` so you can run:

```bash
cd apps/db
dart run raindrop_cli:raindrop --help
```

## Generating a migration

1. Edit or add schema files under `lib/schemas/` (see Raindrop’s schema APIs: `Schema`, `sqliteTable`, column types, etc.).

2. Generate SQL:

```bash
cd apps/db
dart run raindrop_cli:raindrop generate -n <short_description>
```

- **`-n` / `--name`** — Required. Becomes part of the migration tag (e.g. `0001_add_user_email`).
- **`--dry-run`** — Prints the SQL without writing files.

3. Review the generated `migrations/NNNN_<name>.sql`, then commit it together with `migrations/meta/` (journal + snapshots).

4. Optional: inspect CLI state:

```bash
dart run raindrop_cli:raindrop status
```

## Applying migrations in the app

`openZonaiDatabase()` loads every `migrations/*.sql` file (sorted by filename), builds `Migration` values (tag = basename without `.sql`), then runs `migrate(db, migrations)`.

```dart
import 'package:zonai_db/zonai_db.dart';

final db = await openZonaiDatabase();
// migrate() has already run; db is ready.
```

**Working directory:** the default migrations path is `./migrations` relative to the process current directory. Run the app with cwd `apps/db`, or pass `migrationsDirectory` explicitly:

```dart
await openZonaiDatabase(
  migrationsDirectory: fs.directory('/absolute/path/to/apps/db/migrations'),
);
```

For shipped apps you may bundle `migrations/` next to the executable or use a resolved path; tests can point at a temp folder.

You can also call `loadMigrationsFromDirectory(dir)` yourself if you open the DB elsewhere.

## Checksums and changing old migrations

After a migration has been applied to a database, Raindrop stores a **checksum** of its SQL. If you change that migration’s source text later, the next `migrate()` call throws **`MigrationChecksumMismatch`**. That is intentional: applied migrations must not be edited in place.

**Do instead:**

- Add a **new** migration with `generate` that performs the fix (add column, alter, etc.), or
- During development only, use a **new SQLite file** or delete the dev database so migrations run from a clean state (never do this blindly on production data).

Renaming only the default file is supported via `openZonaiDatabase(databaseFileName: '...')` so you can point at a fresh file without touching an old one.

## Typical workflow

1. Change `lib/schemas/*.dart`.
2. `dart run raindrop_cli:raindrop generate -n describe_change`.
3. Run tests / app; confirm DB upgrades on existing dev DBs (from `apps/db` so `./migrations` resolves).
4. Commit schema + `migrations/` (including `meta/`).

## See also

- Raindrop example config: `libs/raindrop/packages/raindrop_sqlite/example/raindrop.yaml`
- `package:raindrop` — `migrate`, `Migration`, `MigrationChecksumMismatch`
