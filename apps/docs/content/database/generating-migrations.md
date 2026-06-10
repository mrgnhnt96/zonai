---
title: Generating Migrations
description: How to generate SQL migration files from schema changes.
---

## The Command

```bash
zonai db migrate generate
```

Aliases: `g`, `gen`

Flags:

| Flag            | Short | Description                                                                    |
| --------------- | ----- | ------------------------------------------------------------------------------ |
| `--name <name>` | `-n`  | Adds a human-readable suffix to the filename (e.g. `--name add_avatar_column`) |
| `--dry-run`     |       | Prints the SQL that would be generated without writing a file                  |

## When to Generate

Run after any schema change:

- Adding or removing a table
- Adding a column to an existing table
- Adding or removing an index
- Before running the server for the first time (to generate the initial `CREATE TABLE` statements)

## How It Works

Zonai compares your current schema definitions against the snapshots of the schemas and generates the minimal SQL to bring the database in line with the schema:

- New table → `CREATE TABLE ...`
- New column on existing table → `ALTER TABLE ... ADD COLUMN ...`
- New index → `CREATE INDEX ...`

Example output for adding a new `posts` table:

```sql
CREATE TABLE IF NOT EXISTS "posts" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "created_at" INTEGER NOT NULL,
    "updated_at" INTEGER NOT NULL
);
```

## Dev Shortcut

Press `m` while `zonai serve` is running to trigger generation without leaving the server. The migration file is created and immediately applied — no restart needed.

## What Zonai Does NOT Generate

Zonai does not generate destructive DDL to prevent accidental data loss:

- **DROP TABLE** — removing a table from the schema does not generate a drop migration
- **DROP COLUMN** — SQLite's limited `ALTER TABLE` support makes this non-trivial; Zonai skips it

If you need to drop a table or column, write the migration SQL by hand and place it in `migrationsPath` with a higher timestamp than the most recent migration.

## Always Review Before Production

The generated SQL is plain `CREATE TABLE`, `ALTER TABLE`, and `CREATE INDEX`. Review it before applying to a production database. The `--dry-run` flag is useful for a quick sanity check before committing.
