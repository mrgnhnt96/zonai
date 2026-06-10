---
title: Applying Migrations
description: How to apply pending migrations to the database.
---

## The Command

```bash
zonai db migrate apply
```

Alias: `up`

Applies all pending (not-yet-applied) migrations in timestamp order. Safe to run multiple times — already-applied migrations are recorded in the `_migrations` table and skipped.

## Auto-Apply at Server Start

`zonai serve` applies pending migrations automatically before opening the HTTP listener. In most workflows — dev and production alike — you don't need to run `apply` manually.

Startup order:
1. Compile workers (dev mode only)
2. Apply pending migrations
3. Ping workers
4. Accept requests

## Disabling Auto-Apply

```bash
zonai serve --no-auto-migrate
```

Starts the server without applying any migrations. Useful when you want to manually review and control migrations in production:

```bash
# Review migrations first
zonai db migrate apply --dry-run  # (if supported, or inspect .sql files directly)

# Apply after review
zonai db migrate apply

# Then start the server
./zonai serve --release
```

## What Happens During Apply

Each migration file runs inside a SQLite transaction:

- **On success**: the migration filename is recorded in `_migrations`, the transaction commits, and Zonai moves to the next file.
- **On failure**: the transaction rolls back. The migration is NOT recorded. The server reports the error and does not start.

Migrations run one at a time, in order. A failure stops the process at that file — later migrations do not run.

## Checking Migration Status

The `_migrations` table in the SQLite database records every applied migration:

```sql
SELECT * FROM _migrations ORDER BY applied_at;
```

Server startup logs also print the names of any pending migrations before applying them.
