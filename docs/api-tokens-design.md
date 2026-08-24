# API tokens — design and build plan

Status: **usable**. Written 2026-08-24. §11 is the build order. Steps 1-5 and 9 are
built: `zonai db token create` mints a credential with no sign-in and no expiry, it
authenticates against `/db`, its scope is enforced ahead of the rules, and it is
revocable on the next request. [api-tokens.md](api-tokens.md) is the user-facing
doc. Still to come: per-token rate limiting (6), `last_used_at` writes (7), and the
dashboard screen (8).

A zonai deployment today has exactly one way to obtain a credential for `/db`: sign in
as a row in an auth collection and receive a JWT that expires (`jwtExpiresIn`, default
14 days) and is revoked the moment it is refreshed. That is correct for a person in a
browser and unusable for everything else — a nightly backup script, a CI job, an ETL
worker, a partner integration, a `curl` in a runbook. None of those has a password to
type, a mailbox to receive an OTP in, or anyone awake to re-authenticate them when the
token lapses.

This adds a second credential kind: an **API token** — issued out of band, valid until
revoked, and scoped to a named subset of the database.

---

## 1. What the request actually needs

"Without expiration, or without needing sign-in credentials" is two independent
properties, and both matter:

| Property | Why the current JWT fails it |
| --- | --- |
| **No expiry** | `JwtGenerator.verify` rejects any token past `exp`, and `Jwt.fromJson` requires `expiresAt` to be a number (`json['expiresAt'] * 1000`). There is no representable "never". |
| **No sign-in** | `_createJwt` (`apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/auth.dart:221`) needs a resolved auth-collection row and is only reachable from an auth flow that verified a credential. |

A third property is not in the request but is not optional, and it is the reason most of
this document exists:

| **Revocable, individually, without a redeploy** | A credential that never expires and cannot be withdrawn is a permanent key to the database. The only safe form of "forever" is "until someone says otherwise." |

And a fourth, which is what separates this from a service-role key:

| **Scoped** | The default rules deny everything except admin tokens (`docs/rules.md` — "Default behavior"). So the naive implementation — mint an admin JWT that never expires — produces a credential that can read and write every collection in the database, forever. That is the footgun, not the feature. |

---

## 2. The decision that shapes it

> **The credential on the wire is an opaque random string, not a JWT. Only its hash is
> stored. Server-side it resolves into an ordinary `Jwt` identity, so every existing rule,
> operation, and worker sees something it already understands.**

Four reasons, in order of weight:

1. **A JWT cannot express "never expires" without weakening the verifier.**
   `JwtGenerator._isExpired` returns `false` when `exp` is absent — an accident of
   `exp != null` on the `default` branch, not a decision. Building a feature on it turns
   an accident into a contract and makes "a token with no `exp`" valid forever *for every
   code path that verifies a JWT*, including the ones that must keep rejecting it.

2. **A JWT ties every API token to `jwtSecret`.** Rotating the signing secret — the
   documented response to a suspected leak — would silently invalidate every integration
   at once. Worse, the reverse: a leaked `jwtSecret` lets an attacker mint API tokens,
   and `previousJwtSecrets` keeps the retired one live on purpose. An opaque token's
   validity depends only on a row existing, so rotation and token lifetime are
   independent facts.

3. **Minting must work with no secret at hand.** The "without sign-in credentials" path
   is `zonai db token create` on the server box. With an opaque token that needs only DB
   write access — the same posture `_revokeAdminInviteFromCli` already takes. With a JWT
   it needs the signing secret too.

4. **Revocation is already a DB read.** `_validateJwt` looks up `_jwt` on *every*
   request today (`__auth_utils.dart:271`). Resolving an opaque token costs the same one
   read, so the opaque design is not paying a performance price the JWT design avoids.

The counter-argument — "now there are two credential formats on the wire" — is real and
is answered by the prefix in §4: the two are distinguishable before either is parsed, so
nothing has to guess.

---

## 3. The identity: `ApiTokenJwt`

`Jwt` is the currency of the entire authorization layer. It is what rules receive
(`TableRules.canList(Jwt? jwt)`), what row rules filter on, and what crosses the worker
IPC boundary — `Request.fromJson` rebuilds it with `Jwt.maybeFromJson(json['jwt'])`
(`libs/zonai_schema/lib/src/handlers/messages/request.dart:40`). An API token that did
not become a `Jwt` would need a parallel path through all of it.

So: a new `final class ApiTokenJwt implements Jwt`, in the shape `CronJwt` and
`ProvisioningJwt` already established (`libs/zonai_schema/lib/src/types/`).

```dart no-analyze
final class ApiTokenJwt implements Jwt {
  ApiTokenJwt({
    required this.tokenId,
    required this.name,
    required this.scope,
    required this.admin,
    required this.claims,
    this.boundUserId,
    this.boundTable,
  });

  static bool isApiTokenPayload(Map<String, Object?> json) =>
      json['API_TOKEN'] == true;

  @override
  JwtId get jwtId => JwtId('__api_token__:$tokenId');

  @override
  String get table => boundTable ?? '__api_token__';

  @override
  UnknownId get userId => boundUserId ?? const UnknownId('__api_token__');

  @override
  DateTime get expiresAt => /* the row's expiry, or the far future when null */;

  @override
  bool get isExpired => false; // resolution already decided this

  @override
  Map<String, dynamic> toJson() => {'API_TOKEN': true, ...};
}
```

Three points about that class that are load-bearing, not incidental:

- **`Jwt.fromJson` gets an `API_TOKEN` branch**, next to `CRON` and `PROVISIONING`, so the
  identity survives the round trip into `db_rules` / `db_operations`.
- **`_extractJwt` must reject an `API_TOKEN` payload arriving as a bearer JWT**, with the
  same "this is a security threat, rotate the secret" log the other two sentinels get. A
  signed `{"API_TOKEN": true, "scope": {"tables": "*"}}` would otherwise be a self-service
  admin key for anyone who can sign.
- **`admin` is not read off the token.** §5.

### Bound vs standalone

`boundUserId`/`boundTable` are optional. Left null, the token is a **service identity**:
it belongs to no row, and rules that do `row.ownerId == jwt.userId` will match nothing —
correct, and worth documenting loudly, because it is the surprise.

Set, the token **acts as** a specific auth row: `jwt.userId` and `jwt.table` are that
row's, so every ownership rule already written keeps working unchanged. This is what a
"personal access token" is, and it is the cheap way to give an integration exactly one
user's view of the data. Both are worth having; the CLI flag is `--as <table>/<id>`.

---

## 4. The credential

```
zonai_pat_<43 chars base64url>   # 256 bits from Random.secure()
```

- The prefix is a **format discriminator**, checked before anything else parses the
  bearer value, so an API token is never fed to `JwtGenerator.verify` and a JWT is never
  looked up as a token.
- It is also a **secret-scanner anchor**. A fixed, greppable prefix is what lets GitHub
  push protection, `gitleaks`, and a log-redaction filter recognise the thing. This is
  the entire reason Stripe, GitHub and Slack all prefix theirs.
- **Only `sha256(token)` is stored.** No pepper, no Argon2: the input is 256 bits of
  CSPRNG output, so there is nothing to brute-force and the per-request cost of Argon2
  would be paid on every API call for no gain. (This differs from `$.password` on
  purpose — a human-chosen password *is* brute-forceable.)
- The plaintext is shown **once**, at creation, and cannot be recovered. `zonai db token
  create` prints it to stdout; the dashboard shows it in a copy-once panel.

---

## 5. Storage: `_api_tokens`

A new internal table, added as `000N_internal_update` in
`apps/zonai/lib/src/internal/internal_db_migrations.dart` (regenerate with the command in
that file's header — do not hand-edit), with a raindrop schema at
`libs/zonai_schema/lib/src/internal/tables/api_token_table.dart`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | `ApiTokenId` |
| `name` | TEXT | Human label — "nightly-backup", "vercel-preview". Required. |
| `token_hash` | TEXT | `sha256` hex. **Must be a secret column** (see below). |
| `token_prefix` | TEXT | First 8 chars of the plaintext, for display: `zonai_pat_a1b2c3d4…`. Lets a human match a token in a log to a row without the secret. |
| `scope` | TEXT | JSON — §6. |
| `claims` | TEXT | JSON — merged into `jwt.claims`, so existing `jwt.claims['role']` rules work. |
| `bound_table` / `bound_user_id` | TEXT? | §3. |
| `expires_at` | INTEGER? | **Nullable. Null means never.** |
| `revoked_at` | INTEGER? | Set rather than deleted, so an audit trail survives. |
| `created_at` | INTEGER | |
| `created_by` | TEXT | Admin user id, or `__cli__`. |
| `last_used_at` | INTEGER? | §9. |

`token_hash` must implement `SecretTransformer` so `_sanitizeRows` strips it
(`__utils.dart:688`). That method's own comment records why this matters: an admin-flagged
reader once got Argon2 password hashes back from `/db/list`, and "an offline cracking
target is worth more to an attacker than the account it came from." The same reasoning
applies verbatim here, and more sharply — an API token hash *is* the credential, not a
hash of one.

**That choice also decides how a token is resolved, which was not obvious until it was
built.** `TableOperations._requireFilterableColumn` refuses a `where` that names a secret
column (`SecretColumnFilterException`) — because a strippable-but-filterable column is a
blind oracle: the body never carries the value, the row count does. So the operations
layer *cannot* look a token up by its hash, and resolution has to go through the raindrop
query builder directly, exactly as `_validateJwt` already reads `_jwt`. Not a workaround:
it means `/db` is structurally incapable of being the path a credential is resolved on.

Internal rules (`ApiTokenTableRules` / `ApiTokenRowRules`, beside the existing
`jwt_table_rules.dart`): list and view for `admin.isAdmin`, delete/update for
`admin.canEdit`, **and deny outright when the caller is an `ApiTokenJwt`, at every
level.** A token that can mint or widen a token is a token with no scope at all.

---

## 6. The scope model, and where it is enforced

```json
{
  "tables": ["orders", "line_items"],
  "operations": ["view", "list", "create"],
  "admin": true,
  "canEdit": false
}
```

- `tables`: an allowlist, or the string `"*"`.
- `operations`: a subset of `view`, `list`, `count`, `create`, `update`, `delete`,
  `custom:<name>`.
- `admin` / `canEdit`: whether this token satisfies the **default** rule implementations.
  Without it a token is useless against any collection whose rules were never overridden,
  because the defaults deny everyone else. With it, rules still run — this grants no
  bypass, it only makes the token look like an admin to a rule that asks.

### `admin` here is a grant, not a claim

`_withServerDerivedAdmin` exists because a JWT's `admin` field was once trusted verbatim
and was forgeable. Its fix — re-derive admin from the schema's `AsAdmin` mixin — does not
transfer, because an unbound API token has no table to derive from.

The safety property is preserved by a different route: an API token's `admin` comes from
**a row in `_api_tokens` that only an existing admin (or the CLI, i.e. someone with
filesystem access to the server) could have written**. It is server-side state, not a
claim on the wire, which is the property that mattered. `ApiTokenJwt` must therefore be
**exempt from `_withServerDerivedAdmin`**, the way `CronJwt` and `ProvisioningJwt`
already are — and the code comment must say which of the two reasons applies, or the next
reader will assume the check was forgotten.

For a **bound** token, take the stricter of the two: the row's grant *and* the bound
table's schema-derived status. A PAT for a non-admin user must not become an admin key.

### Two callers of the same token must not share a cached verdict

Found while building: `_jwtCacheKey` keys the table-rule cache on
`table|userId|isAdmin|canEdit|claims`, and for an unbound API token the first two are
the shared `__api_token__` sentinel. Two tokens with the same admin flags and the same
claims — and *different scopes* — were therefore the same cache key, so one token's
verdict (and its `skipRowChecks`) was served to the other. The key now carries the token
id.

### Two enforcement layers

1. **A hard gate, before rules run.** In the choke point that already resolves table
   rules (`_requireTableAccess` / `_requireCustomTableAccess` in
   `parts/__utils.dart:197,278`): if the caller is an `ApiTokenJwt` and
   `(table, operation)` is outside its scope, deny. This is independent of the rules and
   cannot be widened by a permissive rule file.
2. **The existing rules.** Unchanged. Table rules, then row rules.

The denial must be the **same** `PermissionException` shape a rules denial produces. A
distinct error would turn any token into a scanner for which collections exist.

### `"*"` never includes the internal tables

`_api_tokens`, `_jwt`, `_auth_challenges`, `_log`, `_rate_limit`, `_photos`, `_abusers`,
`_oauth_identity` — a wildcard scope excludes all of them, unconditionally. Naming one
explicitly in `tables` is also refused at creation time. Otherwise `"*"` is a path to
reading every session id and every outstanding auth challenge in the database.

### Routes an API token may never reach

`/auth/*` (it has no password to change and no session to refresh), `/admin/*`,
`/maintenance/*`, `/cron/*`, `/email/*`, `/push/*`, and photos.

**Enforced by inverting the default, which is stronger than an allowlist of routes.**
`_extractJwt` takes `allowApiToken`, defaulting to **false**, and only the nine data
paths (`read`, `list`, `count`, `create`, `createMany`, `update`, `custom`, `delete`,
`streamOne`, `streamList`) pass `true`. Every handler that authorizes through
`zonaiDB.parseJwt` gets the refusal without asking for it — and so does any path added
later whose author never thought about API tokens at all. Forgetting fails closed.

The reason those endpoints are refused rather than scoped: a scope is expressed in
tables and operations, which is a vocabulary none of them have. A token "scoped to
orders" has no meaningful answer to *may it purge an internal table* or *may it invite
an admin*, and inventing one per endpoint is how a scope stops meaning anything.

---

## 7. Rate limiting

Today's limiter keys on **client IP alone** — `QueryRateLimit.check(@Query() body, @Ip()
String ip)` (`apps/zonai/lib/gen/server/routes/components/query_rate_limit.dart`), bucketed
by `(client_ip, table, operation)` in `_rate_limit`. That is wrong for this feature in
both directions:

- **Too tight.** Every call from one integration comes from one IP. A backup job hits the
  default 100/min and gets 429s, and there is no per-caller way to raise it.
- **Too loose.** A leaked token used from many IPs is not limited as a token at all.

So: when the request carries an API token, **bucket on the token id instead of the IP**,
with a `rate_limit` field in the token's scope (`{maxRequests, window}`, or `null` for
unlimited). This means the rate-limit guards must see the `Authorization` header — add
`@Header(HttpHeaders.authorizationHeader)` beside `@Ip()` — and the guard resolves the
token id by hash lookup. Note that this puts a DB read in the guard *before* the handler's
own resolution; cache the resolution for the request rather than reading twice.

`--unlimited` should exist and should print a warning, because "no rate limit and no
expiry" is the combination worth being deliberate about.

---

## 8. Generating one

### CLI — the answer to "without sign-in credentials"

```
zonai db token create --name nightly-backup \
    --tables orders,line_items --read --admin --no-expires
zonai db token list [--all] [--json]
zonai db token revoke <id|prefix>
zonai db token delete <id|prefix>
```

Talks to the DB file directly, exactly as `revokeAdminInviteFromCli` does
(`parts/admin/invite_admin.dart:411`). No server needed, no secret needed, no account
needed — filesystem access to the database *is* the authorization, which is the same
trust boundary `zonai db admin add` already assumes.

`--expires 90d` should be easy and `--no-expires` should be explicit, so the durable
credential is a choice someone made rather than a default they inherited.

### Dashboard

An **API tokens** screen beside the existing admin screens: create (with a copy-once
reveal), list (name, prefix, scope, created, last used, expiry), revoke. `last_used_at`
is what makes the list actionable — it is how someone answers "is this still in use?"
before revoking, and without it nobody ever revokes anything.

### HTTP (later)

`POST /admin/tokens` with an admin JWT. Not needed for v1; the CLI and dashboard cover
the real cases. Adding it means an admin session can mint a credential that outlives it,
so it should wait until the dashboard flow is settled.

---

## 9. `last_used_at` without a write per request

A write on every API call would be a real cost on a hot token. Throttle it: keep the last
written value in memory per token id and write only when the current time is more than
five minutes past it. Precision is not the point — "used within the last hour" vs "not
used since March" is the whole decision this field supports.

---

## 10. Client support

Nothing to build. `libs/zonai_client` already injects `Authorization: Bearer <stored
token>` from `ZonaiStorage` via its interceptor, and the documented "Setting a Token
Manually" path (`apps/docs/content/dart-client/authentication.md`) seeds a token
directly:

```dart no-analyze
final server = Server(storage: ZonaiFileStorage(directory: '/var/lib/myapp'));
await server.storage.save('token', 'zonai_pat_…');
```

Two things to add, both small: an `ApiTokenStorage` convenience that wraps a constant
string (an integration has no token *lifecycle* to store), and a check that the
interceptor's X-Auth refresh logic does not try to refresh an API token — it never
receives an `X-Auth` header, so it should not, but that should be a test rather than an
inference.

---

## 11. Build order

Each step is shippable and observable on its own.

1. **`_api_tokens` migration + raindrop schema + internal rules.** Includes the secret-column
   property for `token_hash` and the deny-to-API-tokens rules. Nothing consumes it yet.
2. **`ApiTokenJwt` + `Jwt.fromJson` branch + the `_extractJwt` rejection of `API_TOKEN` on
   the wire.** Test the rejection *first* and red — it is the one that turns a bug into a
   full compromise.
3. **Resolution:** prefix check → hash lookup → revoked/expired → `ApiTokenJwt`, wired into
   `_extractJwt` ahead of `JwtGenerator.verify`. At this point a hand-inserted row works
   against `/db` with no scoping.
4. **`zonai db token create/list/revoke`.** Now it is usable, and every later step is a
   restriction rather than a capability.
5. **The scope gate** in `_requireTableAccess` / `_requireCustomTableAccess`, plus the
   internal-table exclusion and the route denials.
6. **Rate limiting by token id.**
7. **`last_used_at`.**
8. **Dashboard screen.**
9. **Docs:** `docs/api-tokens.md` and `apps/docs/content/authentication/api-tokens.md`.

---

## 12. What has to be tested

The ones that would be embarrassing to miss:

- A signed JWT carrying `{"API_TOKEN": true}` is **rejected** as a bearer token.
- A token cannot read `_api_tokens`, and cannot create or widen a token — through `/db`,
  through a custom operation, and under a `"*"` scope.
- `"*"` returns nothing for `_jwt` and `_auth_challenges`.
- `token_hash` appears in **no** response body from any endpoint — `get`, `list`, `stream`,
  the dashboard's own queries.
- Out-of-scope table and out-of-scope operation produce the identical error to a rules
  denial (same status, same body).
- Rotating `jwtSecret` does not invalidate an API token. This is the test that proves the
  §2 decision, and it is the one a JWT-based implementation would fail.
- A revoked token 401s on the next request, with no restart.
- An expired token 401s; a `null`-expiry token does not.
- A bound token for a non-admin user is not an admin.
- Rate limiting keys on the token, not the IP: two IPs sharing a token share a bucket.

---

## 13. Alternatives considered

**Long-lived JWT for a real user.** Sign in as a service account row, set
`JwtConfig.expiresIn` to ten years. Zero new code. Rejected: it needs a real auth row with
real credentials (so, not "without sign-in"), it has no scoping (so it is all-or-nothing
at the collection level), revocation means deleting a `_jwt` row nobody can find because
they are unnamed, and "ten years" is a lie told to satisfy a verifier. Worth mentioning in
the docs as the thing this replaces.

**A single static service-role key in config.** One secret, unlimited power, like
Supabase's. Rejected on the strength of the existing security assessment: this deployment
model already had `/db` returning password hashes and an `AsAdmin` + open-signup
escalation. A single unscoped, unrevocable, undeletable key is the wrong direction from
there.

**A signed JWT with an `_api_tokens` revocation row** (i.e. keep JWTs, add the table).
Genuinely close, and the second-best option. Rejected for reasons 2 and 3 of §2 — secret
rotation kills every integration, and minting requires the signing secret — neither of
which the extra table fixes.

---

## 14. Open questions

1. **Should an unbound token be `admin` by default?** Making it opt-in is safer and makes
   the first token someone creates appear broken (every default rule denies it). Making it
   the default is friendlier and is how people will actually use it. Recommendation:
   opt-in, with the CLI printing the specific reason when a token is created without it.
2. **Is `custom:<name>` scoping worth v1?** Custom operations already have a rules path of
   their own and the name arrives unvalidated when rules are not linked in-process
   (`docs/rate-limiting.md:122`). Scoping them may need to wait for that.
3. **Per-token column scoping** ("this token may read `orders` but not `orders.notes`").
   Real demand exists for it; it is a much larger change, touching operations rather than
   rules. Out of scope here, but the `scope` JSON should be shaped so it can be added
   without a migration.
