# zonai_schema

Shared relational model for [Zonai](https://mrgnhnt96.github.io/zonai/) — Raindrop schemas, typed IDs, column helpers, and anything else clients and services need to agree on the DB shape.

## Installation

```yaml
dependencies:
  zonai_schema: ^0.1.0
```

## What's in here

- Typed table/column definitions built on Raindrop, shared between the Zonai server and its clients.
- Payload types for the Zonai wire protocol (create, list, update, delete, streaming variants).
- Shared value types: `Id`, `Jwt`, `Where`, `Update`, `EmailAddress`, and friends.

This package intentionally has no dependency on `sqlite3` in its regular
dependencies — see `tool/verify_client_safe_deps.sh` for the regression check
that keeps it that way, so a client that only needs queries and schemas (no
local SQLite delegate) never has to resolve `sqlite3` at all.
