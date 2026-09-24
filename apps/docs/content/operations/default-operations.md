---
title: Default Operations
description: The built-in CRUD operations every table gets without any code.
---

Every table registered with `table()` or `authTable()` automatically gets these operations. The table name is always part of the request body — it is never in the path.

## Endpoints

| Operation     | Method   | Path               | Body location  |
| ------------- | -------- | ------------------ | -------------- |
| `get`         | `GET`    | `/db`              | `?body=<JSON>` |
| `list`        | `GET`    | `/db/list`         | `?body=<JSON>` |
| `count`       | `GET`    | `/db/count`        | `?body=<JSON>` |
| `stream-one`  | `GET`    | `/db/stream`       | `?body=<JSON>` |
| `stream-list` | `GET`    | `/db/stream/list`  | `?body=<JSON>` |
| `stream-count`| `GET`    | `/db/stream/count` | `?body=<JSON>` |
| `create`      | `POST`   | `/db`              | JSON body      |
| `create many` | `POST`   | `/db/many`         | JSON body      |
| `update`      | `PATCH`  | `/db`              | JSON body      |
| `update many` | `PATCH`  | `/db/many`         | JSON body      |
| `delete`      | `DELETE` | `/db`              | JSON body      |
| `delete many` | `DELETE` | `/db/many`         | JSON body      |

Live updates use the `stream-*` routes (and `client.db.listen` in `zonai_client`). See [Streaming (Live Queries)](/operations/streaming).

## Request / Response Shape

Column names in `where`, `order_by`, `object` and `updates` are the **database** column names from your schema (`is_complete`), not the Dart field names (`isComplete`). Rows come back keyed the same way.

Successful responses wrap the result in `data`.

### get — `GET /db`

Pass the body as a URL-encoded JSON string in the `body` query parameter:

```
GET /db?body={"table":"tasks","where":{"id":{"eq":"tk_abc123"}}}
```

Response:

```json
{ "data": { "id": "tk_abc123", "title": "Buy groceries", "is_complete": false, ... } }
```

### list — `GET /db/list`

```
GET /db/list?body={"table":"tasks","limit":20,"offset":0,"order_by":[{"column":"created_at","direction":"desc"}]}
```

Response:

```json
{ "data": { "items": [...], "total": 42 } }
```

`total` is the full count of matching rows, ignoring `limit`/`offset`. Other optional fields: `where`, `group_by` (one column name), and `expand` (a list of reference columns to inline).

### count — `GET /db/count`

```
GET /db/count?body={"table":"tasks","where":{"is_complete":{"eq":true}}}
```

Response:

```json
{ "data": 7 }
```

### stream-one, stream-list, stream-count — `GET /db/stream*`

Long-lived connections that push a new payload whenever the result changes. `stream-one` requires `where`. Prefer `client.db.listen` in Dart — see [Streaming](/operations/streaming) for bodies and behaviour.

### create — `POST /db`

```json
// Request body
{ "table": "tasks", "object": { "title": "Buy groceries", "is_complete": false } }

// Response
{ "data": { "id": "tk_abc123", "title": "Buy groceries", "is_complete": false, "created_at": "...", "updated_at": null } }
```

### create many — `POST /db/many`

```json
// Request body
{
  "table": "tasks",
  "objects": [
    { "title": "Buy groceries", "is_complete": false },
    { "title": "Walk the dog", "is_complete": false }
  ]
}
```

Response: `{ "data": [...] }` — the created rows, in order.

### update — `PATCH /db`

Updates the first matching row (limit 1). `updates` is a list of update entries — see [Update Value Types](#update-value-types):

```json
// Request body
{
  "table": "tasks",
  "where": { "id": { "eq": "tk_abc123" } },
  "updates": [
    { "type": "column", "column": "is_complete", "value": { "type": "literal", "value": true } }
  ]
}

// Response
{ "data": { "id": "tk_abc123", "title": "Buy groceries", "is_complete": true, ... } }
```

### update many — `PATCH /db/many`

Same shape as `update`, but matches all rows satisfying `where`. Optional `limit` caps how many rows are updated. Response: `{ "data": [...] }` — every updated row.

### delete — `DELETE /db`

Deletes the first matching row (limit 1). No response body.

```json
{ "table": "tasks", "where": { "id": { "eq": "tk_abc123" } } }
```

### delete many — `DELETE /db/many`

Same shape as `delete`, but matches all rows satisfying `where`. Optional `limit` caps deletions.

### custom — `PATCH /db/custom/:operation`

A named operation your operations file implements. Same body as `update` (`where` is optional unless you send `updates`); `/many` variant at `PATCH /db/custom/:operation/many`. See [Custom Operations](/operations/overview#custom-operations).

## Where Filters

`where` accepts a shorthand `{ "<column>": { "<op>": value } }` or the canonical `{ "type": "<op>", "column": "...", "value": ... }`.

| Op | Meaning |
| --- | --- |
| `eq`, `gt`, `gte`, `lt`, `lte` | Comparison |
| `in`, `not_in` | Value in / not in a list |
| `contains`, `not_contains`, `starts_with`, `ends_with` | Text match |
| `is_null`, `not_null` | Null check (value ignored) |
| `and`, `or` | Canonical form only: `{ "type": "and", "conditions": [ ... ] }` |

Every column named in `where`, `order_by` or `group_by` is checked against the table's schema first:

- An unknown column is a `400` naming the column.
- A secret column (`$.password`, `$.secret`) cannot be filtered, sorted or grouped on — `400`. Its value is never returned, so letting a caller filter on it would leak it one comparison at a time.

## Auto-Managed Fields

- `id` — generated by Zonai on create
- `$.createdAt` — set on create; skipped by updates
- `$.updatedAt` — set to the current time on every update
- `$.updatedWhen` — set to the current time whenever its watched column changes
- `$.password` — Argon2id-hashed before storage; stripped from every response (see [Password columns](#password-columns))
- `$.serverGenerated` — filled with a placeholder if the client omits it, so your [`insert` override](/operations/overview#filling-in-a-server-generated-value) can set the real value

## Update Value Types

Each entry in `updates` is one of two shapes:

```json
{ "type": "column", "column": "view_count", "value": { "type": "increment" } }
{ "type": "object", "object": { "title": "New title", "is_complete": true } }
```

A `column` entry takes a typed `value`:

| `value` | Scalar column | List column |
| --- | --- | --- |
| `{ "type": "literal", "value": x }` | Set to `x` (including `null`) | Set to `x` |
| `{ "type": "increment" }` | `column + 1` | — |
| `{ "type": "decrement" }` | `column - 1` | — |
| `{ "type": "add", "value": x }` | `column + x` | Append `x` |
| `{ "type": "remove", "value": x }` | `column - x` | Remove every element equal to `x` |
| `{ "type": "add_all", "values": [...] }` | — | Append each value |
| `{ "type": "remove_all", "values": [...] }` | — | Remove elements matching any value |

A `column` name may be a dotted path into a JSON map column (`profile.display_name`) to set one key. An `object` entry sets several columns at once; on a JSON map column its value is merged with `json_patch` (RFC 7396 merge patch) rather than replacing the map.

In Dart, the same shapes are `Update.column(name, UpdateValue.increment())` and `Update.object({...})`.

## Password Columns

A value written to a `$.password` column — on create or update — is hashed with Argon2id before it reaches SQLite, so the plain text is never stored. Two restrictions apply:

| Condition | Result |
| --- | --- |
| The caller is not an admin, or is a read-only admin (`canEdit: false`) | `403` — only an admin can set a password through `/db`. Users change their own through the [auth API](/authentication/password-auth) |
| The value is not a plain string literal (`increment`, `add`, …) | `422` |
