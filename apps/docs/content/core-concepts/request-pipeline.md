---
title: How a Request is Processed
description: The ordered pipeline every HTTP request passes through in Zonai.
---

Every HTTP request in Zonai follows the same fixed, ordered pipeline. Understanding this pipeline is the key to understanding how authorization, throttling, business logic, and side effects all interact.

<Info>

**Streaming requests** (`GET /db/stream*`) use this same pipeline on connect and again as SQLite results change. Prefer streams over client-side polling. See [Live Queries (Streaming)](/operations/streaming).

</Info>

```text
HTTP Request
     ↓
  1. Rate Limit        — throttling (returns 429 if over limit)
     ↓
  2. Rules             — authorization (returns 403 if denied)
     ↓
  3. Operations        — SQL generation (builds the query)
     ↓
  4. SQLite            — execution (the only place data changes)
     ↓
  5. Rules             — row filter (canView checked per returned row)
     ↓
  6. Extensions        — side effects (hooks, email, cascades)
     ↓
Response
```

The order is fixed and not configurable. Each step only runs if the previous step passed.

**Where the logic runs:** on the default project-binary / project-entry path, **rules and operations** execute **in-process** inside the server. Rate limits, extensions, config, and crons still use worker IPC. Set `ZONAI_FORCE_WORKERS=1` to force ops/rules through Mailman workers as well.

## Step 1: Rate Limiting

The rate limit check is always the first stop. It evaluates whether this client IP has exceeded its request quota for this table + operation combination.

- If over limit: returns `429 Too Many Requests` immediately. No rules are evaluated. No SQL runs.
- If within limit: the counter increments and the request proceeds to step 2.
- Tables with an unlimited / `null` policy are cached after the first resolve so later requests skip further rate-limit IPC.

See [Rate Limiting Overview](/rate-limiting/overview).

## Step 2: Rules (Authorization)

After the rate limit passes, rules evaluate whether the requesting JWT is permitted to perform this operation on this table.

- If denied: returns `403 Forbidden` immediately. No SQL runs.
- If allowed: proceeds to step 3.

See [Rules Overview](/rules/overview).

## Step 3: Operations (SQL Generation)

Operations receive the HTTP payload and generate a SQL statement. They do **not** execute the SQL — they return a structured query to the Zonai server, which validates and runs it.

This is where default CRUD behavior lives and where custom operations plug in.

See [Operations Overview](/operations/overview).

## Step 4: SQLite Execution

Zonai executes the generated SQL against the SQLite database. This is the only step that reads from or writes to the database.

Mutating requests (create/update/delete) are **serialized** on the host so concurrent writes do not pile into SQLite's busy timeout. If too many writes are already queued (default cap 64), the server fails fast with **`503`** (`WriteBackpressureException`) instead of waiting. The 503 carries `Retry-After: 1`: a floor rather than a prediction, since the queue drains in milliseconds and one second is the smallest delay HTTP can express. Wait at least that long before retrying rather than re-sending immediately.

Reads (get/list/count) are not serialized against each other, but they are **bounded**: at most 256 may be in flight at once, since concurrent reads share the rules worker's single pipe and would otherwise just grow in latency with no ceiling. A read past that is refused the same way — **`503`** (`ReadBackpressureException`) with the same `Retry-After: 1`. Through 0.9.0 this refusal reached the client as an unmapped `500`; it is a `503` now.

For mutation operations, the `before*` extension hooks run here, before the SQL executes. If a `before*` hook throws, the mutation is aborted and a `400` is returned.

## Step 5: Row Filter (canView)

After the database returns results, row rules decide whether each row may be seen or mutated. Semantics are still per-row: if any row fails, the request returns `403 Forbidden`.

Performance notes:

- List/view checks are **batched** into one rules call for the page (not one IPC hop per row when workers are used).
- If row rules set `requiresPerRowCheck => false` (typical for fully public tables), the host **skips** row-rule work after a successful table-access check.

See [Row Rules](/rules/row-rules).

## Step 6: Extensions (Side Effects)

After the row filter, extension hooks fire (via the extensions worker when the project has extension sources):

- `after*Success` hooks run after a successful mutation. They can queue additional mutations, reads, and emails.
- `after*Error` hooks run if the SQL failed.
- Auth hooks (`onSignUp`, `onSignIn`, `onRefresh`, `onLogout`) run after the corresponding auth SQL.

If the project has **no** extension Dart files (and no internal extensions), the host **skips** the extensions worker entirely.

Extensions can chain up to 10 additional mutations before the chain is capped.

See [Extensions Overview](/extensions/overview).

## Host-side caches

Repeated list/get traffic avoids redundant work after the first resolve: table-access decisions, ops SQL for read/list/count, sanitize column/photo metadata, empty blacklist lookups, and null rate-limit policies are cached in the server process until restart / worker recompile.

## Auth Requests

Authentication requests (`POST /auth/sign-up`, `POST /auth/sign-in`, etc.) follow the same pipeline:

- Rate limiting applies at step 1, same as all other requests.
- Auth rules (`canSignUp`, `canSignIn`, `canPasswordReset`) replace table rules at step 2.
- Auth-specific SQL (insert for sign-up, credential check for sign-in) runs at step 4.
- Auth extension hooks (`onSignUp`, `onSignIn`, etc.) fire at step 6.

## What the Pipeline Does Not Do

- **Not** validate request body shape — that is the operations layer's responsibility
- **Not** parse `Authorization` headers at the pipeline level — JWT verification happens inside rules/auth handling
- **Not** serve static files — Zonai is an API server only
