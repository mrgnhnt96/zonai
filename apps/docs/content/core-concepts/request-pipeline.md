---
title: How a Request is Processed
description: The ordered pipeline every HTTP request passes through in Zonai.
---

Every HTTP request in Zonai follows the same fixed, ordered pipeline. Understanding this pipeline is the key to understanding how authorization, throttling, business logic, and side effects all interact.

```
HTTP Request
     ↓
  1. Rate Limit Worker    — throttling (returns 429 if over limit)
     ↓
  2. Rules Worker         — authorization (returns 403 if denied)
     ↓
  3. Operations Worker    — SQL generation (builds the query)
     ↓
  4. SQLite               — execution (the only place data changes)
     ↓
  5. Rules Worker         — row filter (canView checked per returned row)
     ↓
  6. Extensions Worker    — side effects (hooks, email, cascades)
     ↓
Response
```

The order is fixed and not configurable. Each step only runs if the previous step passed.

## Step 1: Rate Limiting

The rate limit check is always the first stop. It evaluates whether this client IP has exceeded its request quota for this table + operation combination.

- If over limit: returns `429 Too Many Requests` immediately. No rules are evaluated. No SQL runs.
- If within limit: the counter increments and the request proceeds to step 2.

See [Rate Limiting Overview](/rate-limiting/overview).

## Step 2: Rules (Authorization)

After the rate limit passes, the rules worker evaluates whether the requesting JWT is permitted to perform this operation on this table.

- If denied: returns `403 Forbidden` immediately. No SQL runs.
- If allowed: proceeds to step 3.

See [Rules Overview](/rules/overview).

## Step 3: Operations (SQL Generation)

The operations worker receives the HTTP payload and generates a SQL statement. It does **not** execute the SQL — it returns a structured query to the Zonai server, which validates and runs it.

This is where default CRUD behavior lives and where custom operations plug in.

See [Operations Overview](/operations/overview).

## Step 4: SQLite Execution

Zonai executes the generated SQL against the SQLite database. This is the only step that reads from or writes to the database.

For mutation operations (create, update, delete), the `before*` extension hooks run here, before the SQL executes. If a `before*` hook throws, the mutation is aborted and a `400` is returned.

## Step 5: Row Filter (canView)

After the database returns results, each row is passed back through the rules worker. `canView` is evaluated for every row in the result set. If any row returns `false`, the entire request fails with `403 Forbidden` — no data is returned.

For mutations (create, update, delete), this step applies to the row(s) involved. If the row doesn't pass `canUpdate` or `canDelete`, the mutation is aborted with `403`.

See [Row Rules](/rules/row-rules).

## Step 6: Extensions (Side Effects)

After the row filter, extension hooks fire:

- `after*Success` hooks run after a successful mutation. They can queue additional mutations, reads, and emails.
- `after*Error` hooks run if the SQL failed.
- Auth hooks (`onSignUp`, `onSignIn`, `onRefresh`, `onLogout`) run after the corresponding auth SQL.

Extensions can chain up to 10 additional mutations before the chain is capped.

See [Extensions Overview](/extensions/overview).

## Auth Requests

Authentication requests (`POST /auth/sign-up`, `POST /auth/sign-in`, etc.) follow the same pipeline:

- Rate limiting applies at step 1, same as all other requests.
- Auth rules (`canSignUp`, `canSignIn`, `canPasswordReset`) replace table rules at step 2.
- Auth-specific SQL (insert for sign-up, credential check for sign-in) runs at step 4.
- Auth extension hooks (`onSignUp`, `onSignIn`, etc.) fire at step 6.

## What the Pipeline Does Not Do

- **Not** validate request body shape — that is the operations worker's responsibility
- **Not** parse `Authorization` headers at the pipeline level — JWT verification happens inside each worker
- **Not** serve static files — Zonai is an API server only
