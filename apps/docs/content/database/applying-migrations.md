---
title: Applying Migrations
description: How to apply pending migrations to the database.
---

## The Command

```bash
zonai db migrate apply
```

Alias: `up`

Applies all pending (not-yet-applied) migrations in timestamp order. Safe to run multiple times — already-applied migrations are recorded in the `_raindrop_migrations` table and skipped.

## Auto-Apply at Server Start

`zonai serve` applies pending migrations automatically before opening the HTTP listener. In most workflows — dev and production alike — you don't need to run `apply` manually.

Startup order:
1. Compile workers (dev mode only)
2. Apply pending migrations
3. Ping workers
4. Accept requests

## There Is No "Don't Apply" Switch

Pending migrations are applied **every time the database is opened**, in dev and under `--release` alike. `zonai serve --no-auto-migrate` does not change that: it only stops the dev-mode watcher from *generating* new migrations when your schema changes.

To review before anything runs, read the `.sql` files under `.zonai/migrations/` before you deploy them. `--dry-run` exists on `zonai db migrate generate`, not on `apply`.

## What Happens During Apply

Each migration file runs inside a SQLite transaction:

- **On success**: the migration filename is recorded in `_raindrop_migrations`, the transaction commits, and Zonai moves to the next file.
- **On failure**: the transaction rolls back. The migration is NOT recorded. The server reports the error and does not start.

Migrations run one at a time, in order. A failure stops the process at that file — later migrations do not run.

## Checking Migration Status

The `_raindrop_migrations` table in the SQLite database records every applied migration:

```sql
SELECT * FROM _raindrop_migrations ORDER BY applied_at;
```

Server startup logs also print the names of any pending migrations before applying them.
