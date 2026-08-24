---
title: API Tokens
description: A credential for the data API that needs no sign-in and never has to expire.
---

An **API token** is a credential for the data API that needs no sign-in, no mailbox and no password, and can be issued with no expiry at all. It is what a nightly backup script, a CI job, an ETL worker or a partner integration uses to talk to your database.

```
zonai_pat_qT501HohVqtce6xB_EmC9W1lCBnhlDq-PpfWURL_6Xk
```

It is not a JWT. A JWT is issued to a person who signed in, expires (`jwtExpiresIn`, default 14 days) and is revoked the moment it is refreshed — correct for a browser, unusable for a process that has no password to type and nobody awake to re-authenticate it. An API token is an opaque string whose authority is a row: it works until that row says otherwise.

## Creating One

The server does not need to be running. Run this in your project directory:

```
zonai db token create \
  --name nightly-backup \
  --tables orders,line_items \
  --read
```

```
  zonai_pat_qT501HohVqtce6xB_EmC9W1lCBnhlDq-PpfWURL_6Xk

  This is the only time it will be shown. The server keeps only its hash.

  id:         0549432694cd399_pat
  name:       nightly-backup
  tables:     orders, line_items
  operations: view, list, count
  admin:      yes
  expires:    never -- revoke with `zonai db token revoke 0549432694cd399_pat`
```

<Warning>

The token is printed **once** and cannot be recovered. Only its SHA-256 is stored, so there is nothing on the server to read it back out of. Copy it before you close the terminal; if you lose it, revoke the row and mint another.

</Warning>

Like `zonai db admin add`, this command talks to the database file directly — no running server, no session, no JWT signing secret. Write access to the database *is* the authorization, and that is what makes a token obtainable without sign-in credentials at all.

| Flag | Short | Required | Description |
|------|-------|----------|-------------|
| `--name` | `-n` | Yes | What this token is for. An unnamed credential is one nobody ever revokes, because nobody can tell what would break |
| `--tables` | `-t` | Yes | Collections it may reach, comma-separated, or `"*"` for every app collection. Quote the `*` so your shell does not expand it |
| `--operations` | `-o` | Yes, or a shorthand | Any of `view`, `list`, `count`, `create`, `update`, `delete` — or `"*"` for every one. Quote the `*` so your shell does not expand it |
| `--read` / `--write` | | | Shorthand for the read three and the write three |
| `--custom` | | No | Named custom operations, or `"*"` |
| `--no-admin` | | No | Mint a token that is *not* an admin — see [Tokens are admins by default](#tokens-are-admins-by-default) |
| `--can-edit` / `--no-can-edit` | | No | The write half of admin. Derived when unstated: on for an admin token granted `create`/`update`/`delete`, off for a read-only one |
| `--expires` | | No | `90d`, `12h`, `30m`, `45s`, or a bare number of days |
| `--no-expires` | | No | The default |
| `--claims` | | No | JSON merged into `jwt.claims`, so rules already reading `jwt.claims['role']` work unchanged |
| `--as` | | No | `<table>/<row-id>` — act as one auth row, see [Bound tokens](#bound-tokens) |
| `--json` | | No | Machine-readable output, for a provisioning script |

## Using One

Exactly like a JWT — same header, same routes:

```
curl https://your-app.example/db/list?table=orders \
  -H "Authorization: Bearer zonai_pat_qT501Hoh..."
```

With the Dart client, seed it the same way you would any externally obtained token (see [Setting a Token Manually](/dart-client/authentication#setting-a-token-manually)):

```dart
import 'package:zonai_client/server.dart';
import 'package:zonai_client/storage.dart';
import 'package:zonai_client/zonai_client.dart';

Future<void> main() async {
  final server = Server(
    storage: ZonaiFileStorage(directory: '/var/lib/myapp'),
  );
  await server.storage.save('token', 'zonai_pat_qT501Hoh...');

  final client = ZonaiClient.server(server: server);
}
```

No client changes are needed: the interceptor injects whatever is stored, and an API token is just a different string. A token never receives an `X-Auth` header and is never refreshed — there is nothing to refresh, which is the point.

## What a Token Can Reach

Two independent things decide, and both must say yes.

**The scope**, stored on the row, is checked *before* any rule runs. It names tables and operations, and a request outside it is refused no matter how permissive that collection's rules are. A token cannot be widened by editing a rule file — only by editing the row.

**The rules** then run exactly as they do for a signed-in user. A token scoped to `orders` still has to satisfy `OrderTableRules.canList` and `OrderRowRules.canView`.

An out-of-scope request answers with the same `403 {"error":"Forbidden"}` a rules denial produces, so a token cannot be used to discover which collections exist.

### The Wildcard Is Stored, Not Expanded

`"*"` in `--tables`, `--operations` or `--custom` is written to the token's row as the literal `*`, and the gate tests for it on every request. It is never expanded into the list of things that existed at mint time.

That is the point of it. A collection you add next month, a custom operation you name next week, and a built-in operation a later zonai ships are all covered by a token you minted today — no re-mint, no re-deploy of whatever holds the secret.

The trade is worth stating: `*` is a standing grant, not a shorthand. Ticking all six operation boxes and ticking **Every operation** produce different rows, and only the second one keeps up.

### Internal Tables Are Never in Scope

`_api_tokens`, `_jwt`, `_auth_challenges`, `_log`, `_rate_limit`, `_photos`, `_abusers`, `_oauth_identities`, `_cron_jobs`, `_push_jobs` — unreachable under `"*"`, and naming one explicitly is refused when the token is created.

This is absolute rather than configurable because of what the first two hold. A token that could read `_api_tokens` would see every other integration's row; a token that could write it would mint itself a wider token, and the scope would stop meaning anything. `_jwt` is every live session id.

### Only the Data API

`/auth/*`, `/admin/*`, `/dashboard/maintenance/*`, `/cron/*`, `/email/*`, `/push/*` and the photo endpoints all refuse an API token with `401`. So does any route added later — the credential is rejected by default and each data path opts in explicitly, so forgetting fails closed.

Those endpoints are refused rather than scoped because a scope speaks in tables and operations, a vocabulary none of them have: a token "scoped to orders" has no meaningful answer to *may it purge an internal table*.

## Tokens Are Admins by Default

The default rule implementations deny everyone except an admin (see [Default behavior](/rules/overview)). A token that is not an admin is therefore **inert against any collection whose rules were never overridden** — every request denied, with nothing obviously wrong. That is most collections, so a non-admin token reads as broken rather than as narrow, which is why it is not the default.

<Info>

Admin is not a bypass. It makes the token satisfy a rule that asks `jwt.admin.isAdmin`, and nothing more: the scope still bounds it, and every rule still runs. What a token may reach is `--tables` and `--operations`; admin is what lets it reach them at all.

</Info>

`--no-admin` mints one without it. One of two things then has to be true for it to work: either the collection's rules admit it explicitly — usually on `jwt.claims`, which `--claims` populates — or the token is bound to a user with `--as`.

## Bound Tokens

By default a token is a **service identity**: it belongs to no row. `jwt.userId` is a sentinel, so a rule doing `row.ownerId == jwt.userId` matches **nothing**. That is correct — the token owns no rows — and it is the surprise, so it is worth knowing before you debug an empty list.

```
zonai db token create --name partner-sync \
  --tables orders --read \
  --as users/abc123_usr
```

`--as` binds the token to one auth row instead. `jwt.userId`, `jwt.table` and `jwt.user` are that row's, so every ownership rule you have already written keeps working. This is what a "personal access token" is, and it is the cheap way to give an integration exactly one user's view of the data.

A bound token is never more privileged than the row it names. Its admin grant is clamped at resolution to the bound table's own: if that collection does not mix in `AsAdmin`, the token is not an admin token whatever its row says — and if `AsAdmin` is later removed and the app redeployed, every outstanding token bound to it is demoted on the next request.

## The Dashboard

**API tokens** sits on the dashboard's account menu beside **Admins**, and is admin-only — every route behind it answers only an admin JWT for the resolved `AsAdmin` collection.

It mints, lists, revokes and deletes. Minting reveals the credential in a panel that stays until you dismiss it and says out loud that it will not be shown again; the server keeps only the SHA-256, so there is nothing anywhere to read it back out of. A revoked token stays in the list, labelled — a credential that stopped working is exactly the row you are looking for when an integration breaks.

The routes, if you would rather script them:

```
GET    /admin/tokens             every token, revoked ones included
POST   /admin/tokens             mint one; the response carries the plaintext
POST   /admin/tokens/:id/revoke  stops working on the NEXT request
DELETE /admin/tokens/:id         removes the row, record and all
```

`POST` for revoke and `DELETE` for delete, because the row survives one and not the other.

<Info>

An API token is refused on all four. That is not policy: the internal rules deny `create` and `update` on `_api_tokens` to everyone, so this route family is the only path that mints at all — and its gate does not accept an API token. **A token cannot mint a token.**

</Info>

## Listing and Revoking

```
zonai db token list          # live tokens
zonai db token list --all    # including revoked
zonai db token revoke <id>   # stops working; keeps the record
zonai db token delete <id>   # removes the row entirely
```

`<id>` may be a unique prefix of the id `list` prints. An ambiguous prefix is refused rather than guessed — picking the first match for a revoke is how the wrong integration goes down.

Revocation is what makes "never expires" safe. The row is read on every request, so a revoke lands on the **next** one — no restart, no cache to wait out, no redeploy.

`list` shows when each token was last used. It is written lazily rather than on every request: "used this hour" versus "not since March" is the whole decision it supports, and precision would cost a write per request and buy nothing.

## Rate Limits

A token is rate-limited **per client IP**, like any other caller — the limiter runs before the handler that resolves the credential, so it cannot yet see which token is calling. Two integrations behind one NAT therefore share a bucket, and one token spread across many IPs is not aggregated. Per-token limits are planned.

## Security Model

| Property | How |
|----------|-----|
| The credential is never stored | Only `sha256(token)`. The column is a secret column, which the operations layer refuses to filter on — so `/db` is structurally incapable of being the path a credential is resolved on |
| A leaked signing secret cannot mint one | A token is not a JWT and is not verified with `jwtSecret`. Rotating the secret does not invalidate an integration, and leaking it does not create one |
| A signed token *claiming* to be an API token is refused | On both bearer paths, with an alert telling you to rotate the secret — nothing Zonai issues looks like that |
| Revocation is individual and immediate | One row, next request |
| Scope cannot be widened by a rule | The gate runs ahead of the rules dispatch; only the row widens a token |
