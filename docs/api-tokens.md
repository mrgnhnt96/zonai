# API tokens

An **API token** is a credential for the data API that needs no sign-in, no mailbox and
no password, and can be issued with no expiry at all. It is what a nightly backup script,
a CI job, an ETL worker or a partner integration uses to talk to the database.

It is not a JWT. A JWT is issued to a person who signed in, expires (`jwtExpiresIn`,
default 14 days) and is revoked the moment it is refreshed — correct for a browser, and
unusable for a process that has no password to type and nobody awake to re-authenticate
it. An API token is an opaque string whose authority is a row: it works until that row
says otherwise.

```
zonai_pat_qT501HohVqtce6xB_EmC9W1lCBnhlDq-PpfWURL_6Xk
```

## Creating one

```bash
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

**The token is printed once and cannot be recovered.** Only its SHA-256 is stored, so
there is nothing on the server to read it back out of. Copy it before you close the
terminal; if you lose it, revoke the row and mint another.

The command talks to the database file directly. There is **no running server, no
session and no JWT signing secret involved** — write access to the database is the
authorization, the same assumption `zonai db admin add` already makes. That is what makes
a token obtainable without sign-in credentials at all.

| Option | |
| --- | --- |
| `-n, --name` | What this token is for. Required — an unnamed credential is one nobody ever revokes, because nobody can tell what would break. |
| `-t, --tables` | Collections it may reach, comma-separated, or `"*"` for every app collection. Quote the `*` so your shell does not expand it. |
| `-o, --operations` | Any of `view`, `list`, `count`, `create`, `update`, `delete` — or `"*"` for every one. Quote the `*` so your shell does not expand it. |
| `--read` / `--write` | Shorthand for the read three and the write three. |
| `--custom` | Named custom operations, or `"*"`. |
| `--no-admin` | Mint a token that is *not* an admin. See [A token is an admin by default](#a-token-is-an-admin-by-default). |
| `--can-edit` / `--no-can-edit` | The write half of admin. Derived when unstated — on for an admin token granted `create`/`update`/`delete`, off for a read-only one. |
| `--expires=90d` | `90d`, `12h`, `30m`, `45s`, or a bare number of days. |
| `--no-expires` | The default. |
| `--claims='{"role":"reporting"}'` | Merged into `jwt.claims`, so rules already reading `jwt.claims['role']` work unchanged. |
| `--as=users/abc123_usr` | Act as one auth row — see [Bound tokens](#bound-tokens). |
| `--json` | Machine-readable output, for a provisioning script. |

## Using one

Exactly like a JWT — same header, same routes:

```bash
curl https://your-app.example/db/list?table=orders \
  -H "Authorization: Bearer zonai_pat_qT501Hoh..."
```

With the Dart client, seed it once and every request carries it:

```dart no-analyze
final server = Server(storage: ZonaiFileStorage(directory: '/var/lib/myapp'));
await server.storage.save('token', 'zonai_pat_qT501Hoh...');
```

An API token never receives an `X-Auth` header and is never refreshed — there is nothing
to refresh, which is the point.

## What a token can reach

Two independent things decide, and both must say yes.

**The scope**, stored on the row, is checked *before* any rule runs. It names tables and
operations, and a request outside it is refused no matter how permissive that
collection's rules are. A token cannot be widened by editing a rule file — only by
editing the row.

**The rules** then run exactly as they do for a signed-in user. A token scoped to
`orders` still has to satisfy `OrderTableRules.canList` and `OrderRowRules.canView`.

An out-of-scope request answers with the same permission error a rules denial produces —
`403 {"error":"Forbidden"}`, byte for byte — so a token cannot be used to discover which
collections exist.

### The wildcard is stored, not expanded

`"*"` in `--tables`, `--operations` or `--custom` is written to the `_api_tokens` row as
the literal `*`, and the gate tests for it on every request. It is never expanded into
the list of things that happened to exist at mint time.

That is the whole point of it. A collection you add next month, a custom operation you
name next week, and a built-in operation a later zonai ships are all covered by a token
minted today. Expanding at mint would freeze each grant to one particular afternoon, and
the surprise would land months later as a `403` on something the operator believes their
`*` token already covers.

The cost is stated plainly: `*` is a standing grant, not a shorthand. Ticking all six
operation boxes and ticking **Every operation** produce different rows, and only the
second one keeps up.

### Internal tables are never in scope

`_api_tokens`, `_jwt`, `_auth_challenges`, `_log`, `_rate_limit`, `_photos`, `_abusers`,
`_oauth_identities`, `_cron_jobs`, `_push_jobs` — unreachable under `"*"`, and naming one
explicitly is refused when the token is created.

This is absolute rather than configurable because of what the first two hold. A token
that could read `_api_tokens` would see every other integration's row; a token that could
write it would mint itself a wider token, and the scope would stop meaning anything.
`_jwt` is every live session id.

### Only the data API

`/auth/*`, `/admin/*`, `/dashboard/maintenance/*`, `/cron/*`, `/email/*`, `/push/*` and
the photo endpoints all refuse an API token, with `401` and *"An API token is not accepted
here. API tokens authenticate the data API; sign in for anything else."* So does any route
added later — the credential is rejected by default and each data path opts in explicitly,
so forgetting fails closed.

Those endpoints are refused rather than scoped because a scope speaks in tables and
operations, a vocabulary none of them have: a token "scoped to orders" has no meaningful
answer to *may it purge an internal table*.

## A token is an admin by default

The default rule implementations deny everyone except an admin (see
[rules.md](rules.md#default-behavior)). A token that is not an admin is therefore **inert
against any collection whose rules were never overridden** — every request denied, with
nothing obviously wrong. That is most collections, so a non-admin token reads as broken
rather than as narrow, which is why it is not the default.

Admin is not a bypass. It makes the token satisfy a rule that asks `jwt.admin.isAdmin`,
and nothing more: **the scope still bounds it, and every rule still runs.** What a token
may reach is `--tables` and `--operations`; admin is what lets it reach them at all.
Narrowing is the scope's job, not admin's.

`--no-admin` mints one without it. One of two things then has to be true for it to work:
either the collection's rules admit it explicitly — usually on `jwt.claims`, which
`--claims` is there to populate — or the token is bound to a user with `--as`.

`--can-edit` is the write half. It is **derived** when you do not say: an admin token
granted any of `create`, `update` or `delete` carries it, a read-only one does not — so
a `--read` token is never handed a write grant it has no operation to spend. Pass
`--can-edit` or `--no-can-edit` to decide it yourself. It cannot be granted alongside
`--no-admin`: `BaseTableRules.canCreate` checks `canEdit` alone, so the pair apart would
be a live write grant wearing a non-admin label.

## Bound tokens

By default a token is a **service identity**: it belongs to no row. `jwt.userId` is a
sentinel, so a rule doing `row.ownerId == jwt.userId` matches **nothing**. That is
correct — the token owns no rows — and it is the surprise, so it is worth knowing before
you debug an empty list.

`--as=<table>/<row-id>` binds the token to one auth row instead. `jwt.userId`, `jwt.table`
and `jwt.user` are that row's, so every ownership rule you have already written keeps
working. This is what a "personal access token" is, and it is the cheap way to give an
integration exactly one user's view of the data.

A bound token is never more privileged than the row it names. Its admin grant is clamped
at resolution to the bound table's own: if that collection does not mix in `AsAdmin`, the
token is not an admin token whatever its row says — and if `AsAdmin` is later removed and
the app redeployed, every outstanding token bound to it is demoted on the next request.

## The dashboard

**API tokens**, on the account menu beside **Admins** — admin-only, because
every `/admin/tokens` route answers only an admin JWT for the resolved `AsAdmin`
collection.

The screen mints, lists, revokes and deletes. Minting reveals the credential in
a panel that stays until you dismiss it and says out loud that it will not be
shown again — the server keeps only the SHA-256, so there is nothing anywhere to
read it back out of. A revoked token stays in the list, labelled: a credential
that stopped working is exactly the row you are looking for when an integration
breaks, and hiding it turns "revoked" into "vanished".

The routes behind it, if you would rather script them:

```
GET    /admin/tokens             every token, revoked ones included
POST   /admin/tokens             mint one; the response carries the plaintext
POST   /admin/tokens/:id/revoke  stops working on the NEXT request
DELETE /admin/tokens/:id         removes the row, record and all
```

`POST` for revoke and `DELETE` for delete because the row survives one and not
the other. An API token is refused on all four — the gate is `parseJwt` without
`allowApiToken`, so **a token cannot mint a token**, and that is not policy: the
internal rules deny `create` and `update` on `_api_tokens` to everyone, so this
route family is the only path that mints at all.

## Listing and revoking

```bash
zonai db token list          # live tokens
zonai db token list --all    # including revoked
zonai db token revoke <id>   # stops working; keeps the record
zonai db token delete <id>   # removes the row entirely
```

`<id>` may be a unique prefix of the id `list` prints. An ambiguous prefix is refused
rather than guessed — picking the first match for a revoke is how the wrong integration
goes down.

**Revocation takes effect on the very next request.** Resolution reads the row every
time, so there is no cache to wait out, no restart and no redeploy. That is what makes an
unexpiring credential safe to issue: the only sound form of "forever" is "until someone
says otherwise".

`revoke` stamps the row; `delete` removes it. Prefer `revoke`, so *who had access, and
until when* stays answerable.

`zonai db token list` also shows **last used**, which is the field that makes the list
actionable. "Is anything still using this?" has to be answerable before anyone revokes
anything, and without it nobody ever does.

To withdraw everything at once — the break-glass response to a suspected leak — purge
`_api_tokens` from the Maintenance screen. That is no more drastic than purging `_jwt`,
which signs out every user.

## Rate limits

An API token is rate-limited exactly like any other client today: **per client IP, per
collection, per operation**, at whatever policy that collection declares (default
100/minute — see [rate-limiting.md](rate-limiting.md)).

Know two things about that before you deploy an integration.

**One IP is one bucket.** Every request from a backup job or a CI runner shares a
counter, so a job that fans out will hit the limit far sooner than the same volume spread
across users. Raise the collection's policy, or spread the work.

**A leaked token is not limited as a token.** Used from many IPs it gets many buckets.

Bucketing on the token instead of the IP, with a per-token limit, is designed and not yet
built — [api-tokens-design.md §7](api-tokens-design.md).

## Why it is not a JWT

Four reasons, and the first two are the load-bearing ones.

**A JWT cannot express "never expires" without weakening the verifier.** Zonai's verifier
treats a missing `exp` as unexpired — an accident of how the check is written, not a
decision. Building a feature on it would make "a token with no `exp`" valid forever for
every code path that verifies a JWT, including the ones that must keep rejecting it.

**A JWT would tie every integration to `jwtSecret`.** Rotating the signing secret is the
documented response to a suspected leak, and it would silently invalidate every
integration at once. The reverse is worse: a leaked `jwtSecret` would let an attacker mint
API tokens, and `previousJwtSecrets` keeps a retired secret live on purpose. An API
token's validity depends on a row existing and on nothing else, so rotation and token
lifetime are independent facts.

**Minting has to work with no secret at hand** — see `zonai db token create` above.

**Revocation was already a database read.** Every JWT request looks up `_jwt` to check
revocation, so resolving an opaque token costs the same one indexed read.

A signed JWT is therefore *never* accepted as an API token, and a payload shaped like one
is refused on sight with a "rotate the secret" alert: nothing zonai issues looks like
that, so its presence means the signing key has leaked.

## Related

| Topic | Doc |
| ----- | --- |
| Sessions, refresh, and password management | [auth.md](auth.md) |
| Rule defaults and what `admin` satisfies | [rules.md](rules.md) |
| Custom claims on a signed-in session | [operations.md](operations.md#auth-collections) |
| Per-IP limits on the data API | [rate-limiting.md](rate-limiting.md) |
| The design, the alternatives, and what is still to build | [api-tokens-design.md](api-tokens-design.md) |
