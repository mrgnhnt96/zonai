---
title: zonai rules
description: Inspect compiled access rules for each table.
---

Inspect access permissions for each table according to the compiled rules worker. Use this to debug authorization failures.

```sh
zonai rules <subcommand> [flags]
```

## rules list

Show allowed/denied operations for all tables:

```sh
zonai rules list        # alias: ls
zonai rules list --jwt eyJhbGc...
```

Output shows each table and whether `create`, `list`, `view`, `update`, and `delete` are allowed for the given identity.

Without `--jwt`, evaluates as an anonymous request (no JWT).

## rules table

Show the rule result for a specific table and operation:

```sh
zonai rules table tasks update
zonai rules table users view --jwt eyJhbGc...
```

## The --jwt Flag

Pass a JWT token string (without the `Bearer ` prefix) to evaluate rules as an authenticated user:

```sh
zonai rules list --jwt eyJhbGciOiJIUzI1NiJ9...
```

Use case: "does this specific user's token have permission to delete from the posts table?"

## Requirements

The rules worker must be compiled. The server does not need to be running — `zonai rules` spawns the rules worker directly as a subprocess (similar to `zonai cron run`).

Compile workers if needed:
```sh
zonai compile
```
