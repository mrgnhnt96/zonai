---
title: zonai db
description: Database management subcommands — migrations, admin accounts, email, and logs.
---

Direct database operations — migrations, admin accounts, email testing, and data management. Most subcommands work directly on the SQLite file without a running server.

## db migrate

### generate

Generate SQL migration files from schema changes:

```sh
zonai db migrate generate --name add-status-column
zonai db migrate gen -n add-status-column   # aliases: g, gen
zonai db migrate generate --dry-run          # preview SQL without writing files
```

See [Generating Migrations](/database/generating-migrations).

### apply

Apply all pending migrations to the database:

```sh
zonai db migrate apply   # alias: up
```

See [Applying Migrations](/database/applying-migrations).

## db admin

### add

Create an admin account in an auth table:

```sh
zonai db admin add --email admin@example.com --password secret123
zonai db admin add -e admin@example.com -p secret123 --data '{"name":"Admin"}'
```

| Flag | Short | Description |
|------|-------|-------------|
| `--email` | `-e` | Admin email address (required) |
| `--password` | `-p` | Admin password (required) |
| `--data` | `-d` | Extra JSON fields to merge into the row |
| `--no-verify` | — | Skip email verification for this account |

### list

List every admin account (id, email, and any other non-secret columns — never the password hash):

```sh
zonai db admin list
zonai db admin ls   # alias
```

### reset-password

Reset an existing admin account's password. Use this to recover a deployment where an admin account exists but nobody has the password:

```sh
zonai db admin reset-password --email admin@example.com --password newSecret123
zonai db admin reset -e admin@example.com -p newSecret123   # alias
```

| Flag | Short | Description |
|------|-------|-------------|
| `--email` | `-e` | Admin email address (required) |
| `--password` | `-p` | New admin password (required) |

### remove

Remove an existing admin account. Makes `add` recoverable — a removed email can be re-added later:

```sh
zonai db admin remove --email admin@example.com
zonai db admin rm -e admin@example.com   # aliases: rm, delete
```

| Flag | Short | Description |
|------|-------|-------------|
| `--email` | `-e` | Admin email address (required) |

See [Admin Accounts](/authentication/admin-accounts).

## db email

### test

Send a test email to verify SMTP configuration:

```sh
zonai db email test --to me@example.com
zonai db email test -t me@example.com --template password_reset
```

### template create

Create a new custom email template file:

```sh
zonai db email template create order_confirmation
```

See [Custom Templates](/email/custom-templates).

## db logs

### Where logs are stored

`_log` lives in its own database file, `zonai_log.sqlite`, alongside
`zonai.sqlite` in the data directory. `_rate_limit` gets one too,
`zonai_rate_limit.sqlite`. Both are joined back onto the connection with
SQLite's `ATTACH`, so nothing about querying them changes — the table API, the
dashboard and `zonai db logs` all reach them by name as before.

These two tables are *disposable*: high churn, bounded retention, and nothing
worth reconstructing after a crash. That is what earns them a file of their
own, and it buys three things that are impossible on a shared database:

- `VACUUM` takes its exclusive lock on the disposable data instead of on your
  tables, which is what makes reclaiming space from a cron viable at all
- deleting the file becomes a legitimate recovery step, and it is the only one
  that does not require a write to the volume that has run out of room
- a page cap becomes expressible, since a cap bounds a *file* — on a shared
  database it would be hit by whichever write arrived first, application
  inserts included

`_rate_limit` gains one more: it is written on every request that reaches a
limited operation, and that churn no longer competes for the application
database's write-ahead log.

If you want a hard guarantee that `_log` can never be what fills a volume, [`logDatabaseMaxSize`](/configuration/zonai-yaml#logdatabasemaxsize) puts a ceiling on that file. It is off by default — a cap that is reached stops log writes, which costs observability exactly when you need it.

Databases created before this change are moved on the next server start.
**Existing rows are dropped rather than copied** — the deployments that need
the split most hold millions of them on volumes with no room to copy
anything. Their pages return to `zonai.sqlite`'s freelist, so run
`zonai db logs clear --vacuum` afterwards to hand that space back to the
operating system.

### clear

Delete records from the `_log` table:

```sh
zonai db logs clear                    # aliases: delete, rm
zonai db logs clear --older-than 7d    # keep the last week
zonai db logs clear --vacuum           # also shrink the file on disk
zonai db logs clear --vacuum --force   # skip the confirmation (alias: -f)
```

`--older-than` takes a number followed by `s`, `m`, `h`, `d` or `w` — for
example `30m`, `24h`, `7d`, `2w`. Without it, every record is deleted.

#### Reclaiming disk space

Deleting rows does not shrink the database file. SQLite keeps the emptied
pages on an internal freelist and reuses them for future writes, so a `clear`
that removes millions of records can leave the file exactly as large as it
was. `clear` says so when it happens.

`--vacuum` rewrites the file from its live pages only and returns the
difference to the operating system. It rewrites **both** `zonai.sqlite` and
`zonai_log.sqlite`: new log deletes free pages in the log file, but a database
upgraded from before the split has its old `_log` pages on `zonai.sqlite`'s
freelist. It prompts first, because the rewrite:

- needs roughly **twice the current file size** free on disk, since SQLite
  builds a complete copy before swapping it in
- takes time proportional to the file size — a large database can take minutes
- holds an exclusive lock throughout, so a running server blocks on writes

Answering no cancels the command; nothing is deleted. Pass `--force` to skip
the prompt in scripts.

This matters most on databases created before v0.6.2, which persisted
`trace`- and `request`-level entries to `_log`. Those levels are no longer
written, but rows already on disk stay until they are cleared and vacuumed.

## db clear

Delete the SQLite database files entirely — `zonai.sqlite`, `zonai_log.sqlite`
and `zonai_rate_limit.sqlite`, along with their WAL sidecars:

```sh
zonai db clear          # prompts for confirmation
zonai db clear --yes    # skip confirmation (alias: -y)
zonai db clear --reset  # alias
```

**Destructive — all data is lost.** Migrations re-apply on next server start. Use in development to reset to a clean state.
