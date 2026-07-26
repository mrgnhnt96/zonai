# Known issues

Bugs found incidentally while integrating an external client app against
zonai on 2026-07-24/25. Neither is caused by or related to that work — both
are pre-existing and reproduce identically on a clean checkout with no
schema/endpoint changes at all. Filed here so a fix can be picked up
independently.

**Update 2026-07-25: both fixed.** `BlackList implements LifecycleComponent`
now — confirmed by regenerating `.revali/` and finding `BlackListGuard(di)`
wired into `auth`/`db`/`img`/`email`'s generated routes. `schema_table_discovery.dart`'s
`AnalysisContextCollection` resolution issue is fixed too — confirmed by
re-running `dart run tool/generate_internal_db_artifacts.dart --migrate
--name <table>` from `apps/zonai` against a scratch table added under
`libs/zonai_schema`, which succeeded and produced a real migration file.
Re-ran `dart analyze`/`dart test` across `libs/zonai_schema`, `apps/zonai`,
`apps/server` — same results as before; nothing regressed. Left below for
reference/history.

**Update 2026-07-26: fixed.** Root cause was on the **host** side, not the
worker side the "suggested fix" below points at — `MessageHandler`'s
`_pendingHostReplies` (worker-side) was already correctly keyed by request
id and never confused two in-flight requests. The actual bug was
`Mailman._send`/`_sendOnce` in `apps/zonai/lib/src/db_mutator/mailman.dart`:
it fully serialized each outgoing request through `_sendChain`, including
the *wait for the worker's reply*, not just the stdin write. `_list`'s
per-row `_requireRowAccess`/`_requireTableAccess` always calls back into
the same `RulesMailman` to check row/table rules (`__utils.dart`) — so when
a row rule's own `get.one`/`get.many` needs the host to answer a nested
`GetRecordRequest`, satisfying that read calls `zonaiDB.list`, which calls
`RulesMailman.send(...)` again for the *nested* table's row rules. That
nested send queues behind `_sendChain`, which is still occupied waiting on
the *outer*, still-unanswered request — a real circular wait, not just a
slow path. It only ever resolved because `_sendOnce`'s hardcoded 1-second
`.timeout()` forced the outer request's entry out of `_pendingResponses`,
unblocking the chain — at which point the outer request's real (late)
reply arrived with nowhere to land, logged as `Received response for
unknown request` (or `Received error for unknown request`, if the nested
call itself failed first). **Fixed** by splitting `_send` into a
`_writeOnce` step (still serialized via `_sendChain` — restart-check,
process start, the actual stdin write) and a separate, unserialized
`_awaitOnce` step (the timeout-guarded wait for the reply), so a reentrant
send to the same worker no longer queues behind its own outer request.
**How this was confirmed**: added a scratch row rule
(`PostRowRules.canView` in `apps/playground`) that calls
`get.one(tableName: 'companies', ...)`, compiled and ran the real
playground server end to end (not a unit test — this app has no existing
Mailman test coverage), and hit `GET /db/list?table=posts` for real.
Before the fix: reproduced the exact symptom in the report below,
including a real `TimeoutException after 0:00:01.000000` at
`Mailman._sendOnce` and a live `[RULES_EXE]: Received error for unknown
request` log line. After the fix: the same call resolves in well under a
second with no timeout and no unknown-request log line, end to end. Left
below for reference/history.

## 8. `get.*`/`AuthOperations.addClaims` deadlock the issuing worker if that worker is itself mid-request — "unsafe reentrant IPC," not just "slow"

**Severity: silently breaks every request through the affected worker, not just the one that triggered it.** Found 2026-07-26 while building `override_canvas`'s organization-collaborators feature (a row needing to check "does the caller have access to this *other* table's row" as part of its own access decision). Not caused by or specific to that feature — it's a property of the generic `get`/`mutate` IPC mechanism (`libs/zonai_schema/lib/src/handlers/messages/deps/__get.dart`, wired up generically in `message_handler.dart`) combined with how every worker type (rules, operations, extensions, cron) shares the exact same `MessageHandler` request/reply loop.

**The reproduction, in two independent forms:**

1. A row rule calling `get.*` to look up a *different* table, where the caller is itself in the middle of answering an incoming `RowRulesRequest`:
   ```dart
   // OrganizationCollaboratorRowRules.canCreate
   Future<bool> canCreate(Jwt? jwt, OrganizationCollaborator row) async {
     final organization = await get.one(tableName: 'organizations', where: Eq('id', row.organizationId.value), jwt: CronJwt());
     return organization != null && organization['owner_id'] == jwt?.userId.value;
   }
   ```
   Every request to `POST /db` on ANY table failed with the rules worker logging:
   ```
   [RULES_EXE]: Received response for unknown request: response/.row.can_access
   ```
2. `AuthOperations.addClaims` calling `get.many` while answering an incoming `GetJwtConfigOperationRequest` (fired on every sign-up/sign-in/refresh):
   ```dart
   @override
   Future<Claims> addClaims({required Jwt jwt}) async {
     final owned = await get.many(tableName: 'organizations', where: Eq('owner_id', jwt.userId.value), jwt: CronJwt());
     return Claims({'ownedOrganizationIds': [for (final r in owned ?? const []) r['id'] as String]});
   }
   ```
   Broke *every* sign-up and sign-in in the whole app (not just requests touching organizations), logging:
   ```
   [OPERATIONS_EXE]: Received response for unknown request: response/.auth.get_jwt_config
   ```

Both cases: the worker is currently handling an incoming request it must eventually reply to (`RowRulesRequest`/`GetJwtConfigOperationRequest`), and while handling it, issues its *own* outgoing request (`get.one`/`get.many` → `GetRecordRequest`) back to the host through the same stdin/stdout channel. The reply that comes back gets misattributed to the wrong pending request — the error names the *original incoming* request's own path (`.row.can_access`, `.auth.get_jwt_config`), not the nested one, suggesting the host/worker's reply-correlation gets confused the moment a worker has both an unanswered incoming request and an outstanding outgoing one at the same time.

**What is *not* affected, confirmed by contrast**: `get.one`/`get.many` called from inside an **Extension**'s `beforeCreate` (e.g. `RecordingExtensions.beforeCreate`, `AssetExtensions.beforeCreate`, `OrganizationCollaboratorExtensions.beforeCreate`) works reliably — used successfully throughout this whole session, dozens of passing tests, including immediately after the two bugs above were found and worked around. `beforeCreate` is structurally the same shape (an incoming `CreateExtensionRequest` needing a reply, with a nested outgoing `get.one` mid-handling), so the safe/unsafe boundary isn't simply "hook type" — it may be specific to the `RowRulesRequest`/`GetJwtConfigOperationRequest` request paths, or to rules/operations workers specifically vs. extensions workers; not fully isolated here. `mutate.*` (fire-and-forget, no reply awaited — confirmed via the existing `CleanupExpiredRecordingsCron`) was not implicated either way, since it doesn't wait on a nested reply.

**Not fixed here.** Worked around in `override_canvas` by not doing this at all: `OrganizationCollaboratorRowRules`/`OrganizationRowRules`/`ClientAppRowRules`/`RecordingRowRules` only do synchronous comparisons against `jwt`/the row's own already-attested fields (the same self-attested-then-extension-verified pattern `Recording.ownerId` already used), and the `addClaims` experiment was reverted entirely. This closed off a legitimate use case (row rules deciding access based on a separate table, e.g. a dynamic collaborator list) without a live lookup or JWT claim.

**Suggested fix, for whoever picks this up**: audit `MessageHandler`'s `_pendingHostReplies` bookkeeping (`handlers/messages/message_handler.dart`) for a case where a worker sends an outgoing request *while* an incoming request's own handler is still running — confirm whether replies are correlated purely by request id (as the data structure suggests they should be) or whether some part of the pipeline assumes at most one in-flight conversation per worker. A minimal repro harness: a single-file rules-worker test that does `get.one` on an unrelated table from inside `canView`, hit with concurrent `/db` traffic against two different tables, asserting no `unknown request` log lines appear.

**How to verify a fix**: re-add `get.one`/`get.many` to a row rule (or `get.many` to `addClaims`) and confirm real, concurrent request traffic through that worker no longer logs `Received response for unknown request`.

## 7. No CORS support anywhere — a standalone frontend on a different origin from the server cannot call it from a real browser

**Severity: blocks a whole class of deployment** (any frontend that isn't served from the exact same origin as the zonai server) **— not caused by, or specific to, any one endpoint.** Found 2026-07-25 while building `override_canvas`'s asset-resolution-during-replay feature, but it applies to every browser-side call any external frontend makes to zonai — sign-in, generic `/db` CRUD, everything.

**The fact itself, confirmed by reading the source, not assumed:**

```
grep -rn "Access-Control-Allow-Origin\|cors\|Cors\|CORS" apps/server/ apps/zonai/lib/
# zero hits
```

No lifecycle component, middleware, or route anywhere sets any `Access-Control-*` response header. Combined with the universal, standard behavior of every real browser (block a cross-origin `fetch`/`XMLHttpRequest` response from being read by the calling page unless the response carries a matching `Access-Control-Allow-Origin` header — this is not zonai-specific, it's the same-origin policy every browser enforces by default), the conclusion follows without needing to reproduce it live: **any web app served from a different origin (different scheme, host, or port) than the zonai server it talks to will have every one of its API calls blocked by the browser**, regardless of whether the request itself is otherwise perfectly valid — confirmed working fine via `dart:io`-based HTTP clients (curl, Dart VM tests) throughout this session, which is precisely why this went unnoticed: none of those tools are subject to CORS at all, only real browser `fetch()`/`XMLHttpRequest` calls are.

**Why this matters for zonai specifically, not just this one app**: zonai's own docs and examples (`apps/web`, the internal Jaspr dashboard) work today because that frontend is served *by the same server process* it calls — same origin, CORS never enters the picture. But nothing about zonai's actual architecture requires that pairing, and `docs/`'s own framing of "batteries included" backend implies external, independently-hosted frontends are a legitimate use case — override_canvas's `apps/website` is exactly that: a deliberately standalone Jaspr site talking to a separately-deployed zonai server. That combination is silently broken in any real browser today.

**Not attempted here** — this needs real design care, not a quick patch: a naive `Access-Control-Allow-Origin: *` is the common quick fix, but would need auditing against zonai's actual credential model first (this app uses bearer tokens in an `Authorization` header rather than cookies, which meaningfully narrows the usual wildcard-CORS risk profile — a wildcard origin is a real problem specifically for cookie/credentialed requests, less so for header-based bearer auth — but that's a judgment call for whoever actually implements this, not confirmed safe here). At minimum needs: a configurable allowed-origins list (not hardcoded), correct handling of preflight `OPTIONS` requests (not just the actual response), and a decision on whether it's a `LifecycleComponent`/guard (per issue #1's fix) or a different mechanism entirely.

**Workaround for now**: deploy the frontend and the zonai server behind the same origin (a reverse proxy routing `/api/*` to zonai and everything else to the static frontend, for example) — same-origin requests are never subject to CORS regardless of this gap.

## 6. `AsAdmin` grants admin rights to *every account on the table*, not the specific accounts created via `zonai db admin add` — docs fixed, this is a real design footgun to know about

**Severity: critical, if you follow the docs' own primary example as written.** Found 2026-07-25 while adding an admin schema for `override_canvas`, by literally following `docs/rules/jwt-claims.md`'s own example (`with PasswordAuth, AsAdmin` on the app's regular `UserTable`) and then testing the result against a real running server before trusting it.

**Reproduction:**

```
# Schema: `final class UserTable extends AuthTable<User> with PasswordAuth, AsAdmin { ... }`
# users also supports public sign-up (the normal case for an app's user table)

curl -X POST /auth/sign-up -d '{"type":"signUp","table":"users","email":"brand-new@example.com","password":"...","object":{...}}'
# decode the returned accessToken:
#   "admin": { "isAdmin": true, "canEdit": true }
```

A completely fresh, never-privileged, publicly-self-registered account gets full admin claims. This isn't a corner case — it happens for every account on that table, every time, via every auth flow (sign-up, sign-in, OTP, magic link).

**Root cause.** `libs/zonai_schema/lib/src/handlers/operations/db_operations.dart`'s `_getJwtConfig`:

```dart
final admin = switch (ops?.schema) {
  final AsAdmin admin => admin,
  _ => null,
};

return JwtConfigResponse(
  id: request.id,
  config: JwtConfig(
    claims: claims,
    isAdmin: admin != null,           // <-- per TABLE, not per row
    canEdit: admin?.canEdit ?? false,
    expiresIn: expiresIn,
  ),
);
```

`isAdmin` is computed purely from "does this table's schema implement `AsAdmin`" — it has no way to know whether *this specific row* was created via `zonai db admin add` versus a regular sign-up. There is no per-row admin flag anywhere in the design; `AsAdmin` is fundamentally a per-table switch. Every JWT for every row in an `AsAdmin` table gets the same claims, regardless of how that row's account came to exist or which endpoint (`/auth/sign-up`, `/auth/sign-in`, `/auth/admin`, ...) issued the token.

**This makes `AsAdmin` outright unsafe on any table that also accepts public self-registration.** It is only safe on a table dedicated exclusively to admin accounts, where the *only* way a row can ever be created is `zonai db admin add` (which builds/executes SQL directly — see `apps/zonai/lib/src/db_mutator/zonai_db/parts/admin/create_admin.dart` — bypassing rules entirely, so it isn't itself blocked by anything below). Defense in depth still matters: without an explicit `AuthRowRules.canSignUp` override returning `false`, the *public* `/auth/sign-up` endpoint would happily create new rows on that "admin-only" table too (its default `canSignUp` implementation just checks `schema is PasswordAuth`, true for any password-auth table), letting anyone self-register as an admin over HTTP.

**Fixed**: `docs/rules/jwt-claims.md`'s example now uses a dedicated `AdminTable`/`Admin` (not `UserTable`/`User`), states the per-table-not-per-row behavior explicitly up front, and includes the `canSignUp: false` row-rule override as part of the example rather than treating it as optional. **Not fixed** (would be a real, invasive design change, out of scope here): there's no way, as currently designed, to have admin AND non-admin accounts coexist safely in the *same* auth table — if that's ever wanted, `isAdmin` would need to become a real per-row column/claim instead of a per-table marker.

**How this was confirmed** (not just read from source, and not just theorized): built the vulnerable version first (`with AsAdmin` on a table with public sign-up), started a real compiled server, signed up a brand-new account via `/auth/sign-up`, and decoded its JWT — got `isAdmin: true`. Then rebuilt with a dedicated table instead, re-ran the same sign-up against the same server, and confirmed `isAdmin: false`; separately confirmed a direct `POST /auth/sign-up` attempt against the dedicated admin table (`table: "admins"`) is rejected with `403` once `canSignUp` is overridden. See `override_canvas/apps/server/test/integration/admin_security_integration_test.dart` for the regression tests this produced (regular sign-up/sign-in never get admin claims; self-registration on the admin table is rejected; a CLI-bootstrapped admin account signs in with real admin claims).

## 5. `POST /auth/sign-up` on an existing email silently succeeds if the password happens to match — not fixed, root cause not isolated

**Severity: unclear, worth a closer look** — behavior confirmed via real `curl` calls against a live server (not from reading source), but the exact code path producing it wasn't found in the time spent looking (checked `_signUpWithPassword` in `apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/password.dart` end to end — no explicit "check existing email" or "catch unique-violation, fall back" logic visible there; regular, non-auth `insert()` does not exhibit this — confirmed separately by creating duplicate rows on this session's own `organizations`/`client_apps` tables without issue elsewhere).

**Reproduction:**

```
curl -X POST /auth/sign-up -d '{"type":"signUp","table":"users","email":"a@x.com","password":"P1!","object":{...}}'
# → 200, real new user created

curl -X POST /auth/sign-up -d '{"type":"signUp","table":"users","email":"a@x.com","password":"P1!","object":{...}}'
# → 200, SAME user id/name/created_at as the first response — no second row created

curl -X POST /auth/sign-up -d '{"type":"signUp","table":"users","email":"a@x.com","password":"DIFFERENT","object":{...}}'
# → 401 "Invalid password or email"
```

So a repeated sign-up to an already-registered email is **not** rejected outright — it succeeds (200, fresh JWT) if the submitted password happens to match the existing account's, and only fails if it doesn't. Net effect: `/auth/sign-up` is accidentally usable as a second `/auth/sign-in` for password auth, and (more importantly) a client repeatedly retrying a sign-up call (e.g. on a network timeout, unaware the first attempt actually succeeded) will not get a clear "this email is taken" signal — it'll silently get back the original account instead of an error, which could mask real bugs in retry logic.

**Not a credential-guessing vector**: a caller who doesn't know the real password still gets a normal 401, so this doesn't let anyone into an account they don't have the password for. The main risk is semantic/API-contract surprise, not authentication bypass.

**Suggested next step for whoever picks this up**: trace what actually happens to the `INSERT` when the unique index (`users_email_unique` in this app's own schema — see `override_canvas/apps/server/lib/src/schemas/users.dart`) is violated during a sign-up `CreateAuthOperationRequest`. Given the symptom (silently returns the pre-existing row rather than throwing), the most likely places are (a) something in the create-auth SQL path using `INSERT ... RETURNING` with `OR IGNORE`/upsert semantics specifically for auth creates (regular non-auth `insert()` does **not** default to this — see `raindrop_sqlite`'s `insertOrIgnore`, an explicit opt-in extension method, not the default `insert()`), or (b) a `catch` somewhere between the insert failing and the response being built that re-fetches by email and treats it as success. Neither was confirmed; this needs someone to actually add tracing inside `_signUpWithPassword` and watch it hit the duplicate case, not more guessing from outside.

## 4. `get.one` silently drops its `jwt` parameter — fixed

**Severity: correctness/security** — any extension calling `get.one(..., jwt: someJwt)` to grant a lookup elevated or different access than the calling request's own JWT got the **caller's JWT instead**, silently. Found 2026-07-25 while building `RecordingExtensions.beforeCreate` (an anonymous, API-key-authenticated recording upload that needs to read the owning `client_apps` row — which is rules-gated to authenticated owners — to validate the key).

**Root cause.** `libs/zonai_schema/lib/src/handlers/messages/deps/__get.dart`, `_Get`'s constructor:

```dart
_Get(this.many) {
  one = ({required String tableName, required where, offset, jwt}) async {
    final result = await many(
      tableName: tableName,
      where: where,
      limit: 1,
      offset: offset,
      // jwt was accepted here but never forwarded below
    );
    return result?.single;
  };
}
```

`one`'s signature accepts `jwt`, but the body never passes it to `many(...)` — it silently falls through to whatever `many` treats as its default (the calling request's own JWT, effectively ignoring any override).

**How this was confirmed** (not just read from source): passed both a hand-built `Jwt` and a `CronJwt()` sentinel to `get.one(..., jwt: ...)` inside a real extension and printed the JWT actually seen by the rule check on the other end (`ClientAppTableRules.canList`) — logged `jwt=null` every time, matching "caller's real JWT" (an anonymous upload) rather than either override. Fixed by forwarding `jwt: jwt` into the `many(...)` call; re-ran `dart analyze`/`dart test` on `libs/zonai_schema` — clean, no regressions (149/149 passing).

**Practical impact**: any extension trying to do a privileged/differently-scoped internal read via `get.one(jwt: ...)` — e.g. to check something the calling request itself isn't authorized to see directly — silently got the caller's own (often more restrictive, sometimes `null`/unauthenticated) access instead, with no error to indicate the override didn't apply. `get.many` does **not** have this bug — it forwards `jwt` correctly; only the `one` wrapper built on top of it does not.

## 3. `implements Id` classes have broken value equality — fixed for `UnknownId`; still open for the rest

**Severity: correctness, was silently breaking real ownership checks.**
Found 2026-07-25 while adding ownership rules for a scratch table (own
work, not a hand-off item, but recording it here since it's the same
"real pre-existing bug found along the way" category as #1/#2).

`Id` (`libs/zonai_schema/lib/src/types/id.dart`) declares `operator==`/
`hashCode` with real bodies, but every implementer (`UnknownId`, `PhotoId`,
`AbuserId`, `JwtId`, and others — anything doing `implements Id`) does
**not** inherit those bodies: Dart's `implements` only takes on a class's
member *signatures*, never its concrete implementations (that only happens
through `extends`/mixins). Without its own override, an implementer falls
back to `Object`'s identity-based equality. Confirmed empirically (a
throwaway test, not just reading the spec): two separately-constructed
`UnknownId('user_123')` instances compared unequal.

**Practical impact, not just theoretical**: `PhotoRowRules.canUpdate`/
`canDelete` (`libs/zonai_schema/lib/src/internal/rules/photo_row_rules.dart`)
check `jwt.userId == row.ownerId` — both sides are `UnknownId`, built down
two completely different paths (JWT claim decode vs. a DB row read), so
they're never the same object instance. This means that check has
presumably **always evaluated false for the real, legitimate owner** —
a photo's actual owner could never update or delete their own photo via
the generic path. Not verified against a live request (no repro server
run), but the equality behavior itself is directly confirmed.

**Fixed**: `UnknownId` (the class actually used for cross-entity
ownership comparisons everywhere) now has a real `operator==`/`hashCode`.
**Deliberately not fixed**: `PhotoId`, `AbuserId`, `JwtId`, and any other
pre-existing `implements Id` class — same latent bug, but none of them are
compared for equality directly in real logic the way `UnknownId` is
(they're used as primary keys / `.where(column.equals(id))` query values,
which compare via the underlying column value in SQL, not Dart `==`), so
fixing `UnknownId` closes the actually-exercised gap without a broader,
riskier sweep through every internal table file. Worth a full audit at
some point regardless — grep for `implements Id`. Also worth noting: don't
assume "never compared directly" holds forever for a given ID type — it
only takes one new piece of code doing a direct `==` comparison (instead of
going through a query builder's `.equals()`) to turn this into a live bug
for that type too, so re-check this assumption whenever a new direct
comparison shows up on an `implements Id` type.

Regression coverage: `libs/zonai_schema/test/src/types/id_test.dart` —
uses runtime-constructed (non-`const`) instances deliberately, since
`const UnknownId('x')` literals get canonicalized by the compiler and
would accidentally pass via identity even with the bug still present.
Confirmed via deliberate revert that these tests fail without the fix.

## 1. `@BlackList()` generates no guard at all — every annotated controller is currently unprotected

**Severity: security.** Five controllers declare `@BlackList()` expecting
IP-based abuse blocking, but the annotation is never actually wired up as a
guard by Revali's code generator — it is silently a no-op. Confirmed via the
generator source and by inspecting a generated route file; this is not a
runtime/config issue, it cannot work as currently written.

**Affected controllers** (`apps/server/routes/controllers/`):
- `web_controller.dart`
- `email_controller.dart`
- `photos_controller.dart`
- `auth_controller.dart` — most severe: sign-in/sign-up/refresh/reset-password all currently have zero IP-based abuse protection
- `db_controller.dart` — the generic CRUD surface, also currently unprotected

**Root cause.** `BlackList` (`apps/server/routes/components/black_list.dart`):

```dart
final class BlackList {
  const BlackList();

  Future<GuardResult> check(@Ip() String ipAddress) async { ... }
}
```

has the right shape (a `check` method returning `Future<GuardResult>`), but
the class does **not** `implement LifecycleComponent`
(`package:revali_router_annotations`). Revali's server generator only
recognizes an annotation instance as contributing a lifecycle
component/guard when its static type matches that marker — see
`ServerRouteAnnotations._fromGetter` in the resolved `revali_server`
package (pinned via this workspace's `pubspec_overrides.yaml`, currently
`~/.pub-cache/git/revali-c89dd3ed.../constructs/revali_server/lib/converters/server_route_annotations.dart:158`):

```dart
OnMatch(
  classType: LifecycleComponent,
  package: 'revali_router_annotations',
  convert: (object, annotation) {
    lifecycleComponents.add(
      ServerLifecycleComponent.fromDartObject(object, annotation),
    );
  },
),
```

Since `BlackList`'s type never matches `classType: LifecycleComponent`,
`@BlackList()` never reaches this `OnMatch` branch, so it contributes
nothing to `lifecycleComponents` — no guard is ever registered for any
controller annotated with it.

**How this was confirmed** (not just read from source): added a scratch
guard that *does* `implements LifecycleComponent`. Regenerating `.revali/`
twice — once with the scratch guard also missing the `implements` clause,
once with it added — showed the generated route only ever lists a
`guards: [...]` entry in the second case. The exact same experiment applied
to `BlackList` would show the same absence for every controller listed
above; this wasn't repeated here to avoid making an unrelated,
broader-blast-radius change while investigating.

**Suggested fix.** In `apps/server/routes/components/black_list.dart`:

```dart
import 'package:revali_router_annotations/revali_router_annotations.dart'; // or wherever LifecycleComponent is exported from for this workspace's pinned revali version

final class BlackList implements LifecycleComponent {
  const BlackList();

  Future<GuardResult> check(@Ip() String ipAddress) async { ... } // unchanged
}
```

Then regenerate `.revali/` (check `apps/docs/content/*`/root
`docs/GET_STARTED` for the documented codegen step) and confirm each of the
five generated route files above now lists `BlackListGuard(...)` (or
equivalent) in its `guards: [...]`.

**How to verify the fix**: write or extend a route-level test (or a
generated-route inspection, matching how this was confirmed above) that
asserts a request from a row in `abusers` with `blackListed: true` is
actually rejected with `403` on at least one of the five affected
endpoints — today, no such test would catch this, since the annotation
compiles fine and only silently fails to do anything at request time.

## 2. `raindrop_cli`'s migration generator can't resolve schemas outside the calling package

**Severity: blocks migrations for any table added to `zonai_schema`** — this
reproduces for the *first* table the loader tries to resolve regardless of
which table you're actually trying to add.

**Reproduction** (safe to re-run — fails before writing any file, no `.sql`/
journal/snapshot is created, no database is touched):

```
cd apps/zonai
dart run tool/generate_internal_db_artifacts.dart --migrate --name <anything>
```

```
Unhandled exception:
Bad state: Unable to find the context to /Users/morgan/Development/dart_projects/zonai/libs/zonai_schema/lib/src/internal/tables/abusers_table.dart
#0      AnalysisContextCollectionImpl.contextFor (package:analyzer/src/dart/analysis/analysis_context_collection.dart:157:5)
#1      discoverSchemaVariables (package:raindrop_cli/src/runtime/schema_table_discovery.dart:54:32)
#2      RuntimeSchemaLoader.load (package:raindrop_cli/src/runtime/runtime_schema_loader.dart:27:29)
#3      GenerateCommand.run (package:raindrop_cli/src/cli/commands/generate.dart:92:51)
```

(The non-`--migrate` path, `dart run tool/generate_internal_db_artifacts.dart`
with no flag, works fine — it doesn't go through this analyzer-based
schema loader.)

**Root cause.** `apps/zonai/raindrop.yaml`:

```yaml
schemas: ../../libs/zonai_schema/lib/src/internal/tables
```

points outside `apps/zonai`'s own directory (into the sibling `libs/`
package where all schema/table definitions actually live — see
`libs/zonai_schema`'s own description: "Shared relational model for
Zonai... anything else clients and services need to agree on the DB
shape"). `RuntimeSchemaLoader.load` (`libs/raindrop/packages/raindrop_cli/lib/src/runtime/runtime_schema_loader.dart:27-30`) passes the *project* root
(`apps/zonai`) as `packageRoot` and the resolved `schemas:` path as
`schemaDir` into `discoverSchemaVariables`, which then does
(`libs/raindrop/packages/raindrop_cli/lib/src/runtime/schema_table_discovery.dart:49-54`):

```dart
final absRoot = p.normalize(p.absolute(packageRoot)); // apps/zonai only
final collection = AnalysisContextCollection(includedPaths: [absRoot]);
...
for (final path in dartFiles) { // dartFiles come from schemaDir, e.g. libs/zonai_schema/...
  final context = collection.contextFor(path); // throws: path isn't under absRoot
  ...
```

`AnalysisContextCollection` is only told about `apps/zonai`; every file
under `schemaDir` (`libs/zonai_schema/...`) is outside that root, so
`contextFor` throws for the very first file it processes — this has
nothing to do with which table is being added, it would fail identically
for any table.

**Suggested fix.** Include both roots (deduplicated) in
`schema_table_discovery.dart`:

```dart
final absRoot = p.normalize(p.absolute(packageRoot));
final absSchemaRoot = p.normalize(p.absolute(schemaDir));
final includedPaths = {absRoot, absSchemaRoot}.toList();
final collection = AnalysisContextCollection(includedPaths: includedPaths);
```

This is additive — the common case where `schemaDir` is already nested
inside `packageRoot` just gets a harmless duplicate-ish root; the
cross-package case (this repo's actual layout) gets the root it's
currently missing. `libs/raindrop` is a git submodule (fork of
`wolfenrain/raindrop`, branch `zonai`) — this fix belongs there, then
needs the submodule pointer bumped in this repo once merged.

**How to verify the fix**: re-run the exact reproduction command above
from a clean checkout after the fix; it should get past schema discovery
and actually produce a `.sql` migration file for whichever table triggered
it, under `apps/zonai/lib/src/internal/migrations/`.
