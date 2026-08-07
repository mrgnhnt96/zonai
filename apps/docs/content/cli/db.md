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

### clear

Delete all records from the `_log` table:

```sh
zonai db logs clear   # aliases: delete, rm
```

Useful in development when logs have grown too large.

## db clear

Delete the SQLite database file entirely:

```sh
zonai db clear          # prompts for confirmation
zonai db clear --yes    # skip confirmation (alias: -y)
zonai db clear --reset  # alias
```

**Destructive — all data is lost.** Migrations re-apply on next server start. Use in development to reset to a clean state.
