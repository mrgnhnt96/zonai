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
| `--allow-destructive` | | Allows a migration that drops a table or a column (refused otherwise) |

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

## Destructive Changes Are Refused

A schema change can lose data without looking destructive:

- **A table that leaves the schema** generates `DROP TABLE`, and every row in it goes.
- **A table renamed in its schema file** is a new, empty table plus a dropped old one. Its rows do not move.
- **A column that leaves a table** rebuilds the table without it, because SQLite's `ALTER TABLE` can't drop most columns. The column's data goes.

`zonai db migrate generate` refuses all three. It prints what would be lost, writes nothing, and exits non-zero:

```text
Refused to generate migration "cleanup": it would destroy data.
  - it drops table "archive" and every row in it
```

When the loss is what you want, say so:

```bash
zonai db migrate generate --name drop_archive --allow-destructive
```

The migrations `zonai serve` and `zonai dev` generate when you save a schema file never pass `--allow-destructive`. A schema file renamed or deleted in development is refused there too, and it can't quietly become a `DROP TABLE` that ships with your next deploy.

A column that raindrop recognises as **renamed** is not refused. A column that disappears while another with an identical definition appears (same type, nullability, key and default) is treated as a rename, and it keeps its data.

## Always Review Before Production

Review the generated SQL before applying to a production database. The `--dry-run` flag is useful for a quick sanity check before committing.
