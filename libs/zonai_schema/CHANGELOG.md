# Changelog

## 0.4.2

Additive. No export was removed or renamed, and no behaviour that an existing
app relies on changed.

**API tokens.** A credential for something that cannot sign in — a backup
script, a CI job, a partner integration. Issued from the CLI or
`POST /admin/tokens`, with no sign-in involved and optionally no expiry.

- `ApiTokenSecret`, `ApiTokenId`, `ApiTokenJwt`, `ApiTokenScope`, and the
  `ApiTokenBody` payload for the create route.
- The credential is an opaque `zonai_pat_…` string, **not** a JWT. Only its
  SHA-256 is stored, so the plaintext exists exactly twice — in the process
  that generated it, and wherever the operator pasted it. Nothing can recover
  it from a row, which is what makes "shown once, at creation" a fact rather
  than a promise.
- `ApiTokenJwt` is a `Jwt` because `Jwt` is the currency of the whole
  authorization layer — rules take one, row rules filter on one, and the
  worker IPC boundary rebuilds one from JSON. An API-token identity that were
  not a `Jwt` would need a parallel path through all of it.
- A signed JWT carrying the API-token flag is **refused** as a bearer token,
  with the same "rotate the secret" log the `CRON` and `PROVISIONING`
  sentinels get. Accepting one would let anyone who can sign a token mint
  themselves an unscoped admin key. The flag exists for the worker round trip
  and nothing else.
- `ApiTokenScope` is a hard gate evaluated **before** rules, not an input to
  them: an out-of-scope `(table, operation)` is refused however permissive
  that table's rules are, and rules then run as usual and may deny further.
  Widening is only ever possible by editing the row.
- `"*"` for `--operations` is **stored as `"*"`**, not expanded at creation.
  An expanded list would silently freeze the token to the operations that
  existed on the day it was minted.
- `SecretColumn` (`src/column_types/secret_column.dart`), the column type
  `is SecretTransformer` checks see.

**Forced password reset.** `_password_reset_requirements`, one
`(table, user_id)` marker meaning "this account must choose a new password
before a password sign-in will mint a session", with its rules and operations.

- Durable on purpose. The reset *ticket* a gated sign-in hands back is an
  ordinary `_auth_challenges` row with a short expiry; this row is the
  requirement and has to outlive every ticket issued against it. A requirement
  that expired on its own would silently restore the old password — the exact
  failure the feature exists to prevent.

**`beforeSignUp`.** An `AuthExtension` hook that can decline a registration
before any row exists, answering `403` with the app's own reason.

- `SignUpCandidate` and `SignUpDeclinedException`.
- The candidate is deliberately **not** the typed row. The row does not exist
  yet, so building one means `safeCreate` inventing a value for every column
  the body did not supply — and it only knows how to invent for five
  transformers. `is_verified`, on every `AuthTable`, is not one, so
  `decode(null)` threw inside the extension worker and an ordinary *allowed*
  sign-up died before the hook was entered. Widening `safeCreate` would move
  that failure rather than remove it.
- It runs on password, OTP and magic-link sign-up, at request time. On OTP and
  magic link it runs **again** at verify, because the account is created there
  and a challenge is valid for ten minutes — so the hook is **at least once**
  on those two flows and a body with a side effect must tolerate repeating.
- It does not run for a first-seen OAuth or external-IdP identity; those
  decline by returning from `onExternalAuthFirstSeen` without inserting.

**Smaller things.**

- `Jwt.isApiTokenPayload`, and `Jwt.maybeFromJson` now reconstructs an
  `ApiTokenJwt` when it sees that payload.
- `SignUpAuthBody.fromJson` validates rather than casts. A body whose `email`,
  `password` or `object` had the wrong type produced a `500` from a failed
  cast; it now raises `ArgumentError` and the route answers `400`. The `type`
  switch no longer casts either, so a missing or non-string `type` is a `400`
  rather than a crash.
- `maintenance_actions.dart` documents `_api_tokens` and
  `_password_reset_requirements` as purge targets — and flags the second as
  the one entry whose purge is a **weakening**: every other table here becomes
  more restrictive when emptied, while this one quietly releases every account
  an operator forced to reset.
- `internal_db_artifacts.dart` registers the two new internal tables.

## 0.4.1

Purely additive. Nothing was removed, renamed, or changed in behaviour.

- **`Where.isNull(column)` and `Where.isNotNull(column)`.** Two const factories that redirect to the existing `Null` and `NotNull` clauses, so those clauses stay constructible without a caller ever naming those two classes. That matters because `zonai_client`'s barrel cannot export them: a library importing `Null` shadows `dart:core`'s `Null`, since Dart resolves an explicit import ahead of the implicit `dart:core` one. Confirmed by compiling rather than by reasoning about it — in a file importing `package:zonai_schema/payloads.dart`, `Null x; print(x);` fails analysis with `not_assigned_potentially_non_nullable_local_variable`, which is legal against `dart:core`'s nullable `Null`, so the error is the shadowing itself. Additive: `Null` and `NotNull` are unchanged and still exported from this package.

- **`Email.preheader`.** The inbox preview line a mail client shows next to the subject. Rendered into the template as `{{preheader}}` inside a hidden block, so it never paints in the body; without one the client scrapes whatever visible text comes first, which is usually the greeting. Each built-in auth email (`SendOtpEmail`, `SendMagicLinkEmail`, `SendVerifyEmailEmail`, `SendResetPasswordEmail`, `SendAdminInviteEmail`) now ships a default. The OTP one deliberately leaves the code out: the preheader is what renders on a locked phone.
- **`PushPermanentlyRejected.detail`.** The provider's own words, carried as far as a human. `PushRejectionReason` has two values because two is all the fan-out needs, but APNs answers `Unregistered` for an uninstalled app and `BadDeviceToken` for a valid token issued by the *other* environment — both prune correctly, only the second is a deployment mistake somebody can fix. Nullable and never load-bearing: nothing branches on it.
- **Push test-send payloads** (`src/payloads/push_test_send.dart`) and **dashboard metrics payloads** (`src/payloads/dashboard_metrics.dart`), backing the dashboard's test-send, push-queue and sessions panels. `payloads.dart` also now exports `push_outcome.dart` and `DevicePlatform`, which the dashboard needs to name and previously could not reach through that barrel.

## 0.4.0

> **Re-run `zonai compile` after upgrading, and use it with Zonai CLI v0.8.0 or
> newer.** This release adds message vocabulary a worker *dispatches*, and your
> `.zonai/executables/*.exe` keep the old copy until they are rebuilt. The
> `.protocol` stamp will not catch it: that records the IPC framing version, not
> what the messages contain.

**Push notifications.** `push(...)` is now available inside rules, operations
and crons, and hands the fan-out to a checkpointed job table rather than doing it
inline — so a large send survives a restart and cannot block the request that
started it.

- `PushMessage`, `PushJobId`, and the `PushOutcome` result types
  (`PushDelivered`, `PushPermanentlyRejected` with a `PushRejectionReason`,
  `PushTransientlyFailed`).
- `PushConfig` and `ApnsConfig` on `AppConfig.push`, with `PushCredentials` /
  `ApnsCredentials` in file or inline form, and `OnPermanentRejection` deciding
  what happens to a token Apple or Google has rejected for good.
- A `deviceToken` column type (`ColumnShapeKind.deviceToken`), and a declared
  platform column (`DevicePlatform`) that routes each row to APNs or FCM — so
  iOS is reachable without Firebase in the middle.
- The internal `_push_jobs` table and its drain/cleanup crons.

**OAuth, and admin invites.** Sign-in through a provider is now first-class.
Add the mixin and list your providers:

```dart
class Users extends AuthTable with PasswordAuth, OAuth, AsAdmin {
  @override
  List<OAuthProvider> get oauthProviders => [OAuthProvider.google(...)];
}
```

- `OAuthProvider`, with built-in factories named by `OAuthProviderKind` (Google,
  Apple, GitHub, Microsoft, Facebook, Discord, GitLab, LinkedIn) and
  `OAuthProvider.custom(...)` for anything else.
- `OAuthEndpoints`, `OAuthClaimMap`, `OAuthLinking`, `OAuthBrand`, `OAuthIcon`
  and `OAuthProviderPublic` — the last being what the dashboard is given, so a
  client secret never leaves the server.
- `oauth_body` and `admin_invite_body` payloads, the internal
  `_oauth_identities` and `_auth_challenges` tables and their rules, and
  `AuthTable.supportsOAuth`.

**Breaking: two enums gained values.** Before 1.0 that is breaking, and it is
also exactly why `kMinSchemaVersion` moved to 0.4.0 — both are decoded with
`Enum.values.byName`, which throws on a name it does not have, so a v0.8.0 CLI
sending one to an older schema fails at the worker rather than degrading.

- `AuthType` is now `{ password, otp, magicLink, oauth }`.
- `RateLimitOperation` gained `adminInvite`, `oauthStart` and `oauthCallback`.

An exhaustive `switch` over either in your own code will stop compiling until
you handle the new values.

**Behaviour changes, no API change:**

- **The default JWT lifetime is now 24 hours, was 14 days.** Zonai has no
  refresh-token flow, so the lifetime *is* the idle timeout — the old default
  meant a session could not be withdrawn for a fortnight. Set `jwtExpiresIn` on
  `AppConfig`, or per auth table, to choose your own.
- **Admin auth is throttled far below the generic limit**:
  `adminAuthenticatePolicy` and `adminSignInPolicy` now default to
  `RateLimitPolicy.adminAuth` (10 requests / 15 minutes) instead of
  `defaultPolicy` (100 / minute). The only honest traffic these endpoints see is
  a human typing a password.
- **`AppConfig.validate` rejects weak and reused secrets**: a short or
  placeholder `jwtSecret` / `passwordSecret`, the two being equal, and either
  appearing in its own `previous*Secrets` list. A project that was relying on a
  throwaway secret will now fail to start, which is the point.
- **`where` clauses are checked against the table**: filtering on a column that
  is not on the table, or on a secret column such as a password, is refused
  rather than interpolated. This applies to `update` and `delete` too.

**Also added:** storage and maintenance payloads behind the dashboard's
Maintenance screen (`storage_metrics.dart`, `maintenance_actions.dart`,
`formatBytes`), richer `SchemaException` variants, extension request/response
vocabulary, and detection of custom-operation name collisions.

## 0.3.1

**`In` and `NotIn` where-clauses threw `ArgumentError` when sent between a
worker and its host.** Anything that put one on the wire failed before the
request was dispatched — including any rule, operation or cron that calls
`get.*` with an `In`/`NotIn` filter.

> **Re-run `zonai compile` after upgrading.** This changes code a worker
> *dispatches*, and your `.zonai/executables/*.exe` keep the old copy until
> they are rebuilt. The `.protocol` stamp will not catch it: that records the
> IPC framing version, not what the messages contain.

The cause: `serializeWhereValues` ended in `.cast<Object>()`, which returns a
`CastList` rather than a plain `List`. Zonai has two worker transports — a
process worker receives the message encoded as bytes, where any `List` works,
and an **isolate** worker receives the object graph itself. An isolate message
may only contain primitives plus *plain* `List`/`Map` instances, so a
`CastList` is rejected as "a regular instance". Released binaries always use
the isolate transport, so this only ever failed there.

Only `In` and `NotIn` were affected; they are the only clauses whose
serializer builds a collection.

## 0.3.0

**Scheduled cron jobs could not write to the database at all.** Every
`mutate.create` / `mutate.update` / `mutate.delete` queued from a *scheduled*
firing was silently discarded — no error, no entry in `_cron_jobs.error`, at
any row count. Manually-triggered runs were unaffected, which is why this
survived so long. If you have a scheduled job whose writes never appeared,
this was it, and it needs no change on your side beyond upgrading.

The cause: `runWithParent` bound its request-scoped providers with
`includeIfAbsent`, which `scoped_deps` skips when the zone chain already
defines the ref. A scheduled cron always nests — the scheduler starts inside
`runWithParent(StartCronsRequest)` and a Dart timer fires in the zone that
created it — so every firing tagged its mutations with the *startup* request's
id. The host keys pending mutations by parent id and flushes on the matching
response; `CronsStarted` was answered once, at boot, and everything filed
afterwards was parked forever.

Found via a production deployment whose `_log` table reached 4.6M rows and
filled a 1GB volume while its retention cron reported success 13 times.

### Breaking

- **`revali_core` moves to `^3.0.0`** (was `^2.0.0`). If your project pins
  `revali_core` 2.x, or a `revali_router` 4.x that requires it, resolution
  will fail until you move up.

- **Re-run `zonai compile` after upgrading.** This release changes the cron
  IPC vocabulary, and the `.protocol` stamp will not catch a stale worker:
  that stamp records the IPC *framing* version, not the message vocabulary. A
  stale `.zonai/executables/*.exe` keeps the old code.

### Added

- `mutate.purge` — a bulk `DELETE` returning the number of rows removed. Skips
  the read-back, the per-row rules dispatch and the extension hooks that
  `mutate.delete` performs, none of which a retention sweep over millions of
  rows can survive. Restricted to the framework's own tables and to admin
  identities, enforced host-side rather than trusted from the caller. All five
  internal retention crons now use it and report real counts.

- `ReclaimLogSpaceRequest` / `ReclaimLogSpaceResponse` — a cron-to-host RPC
  asking for the log database to be rewritten when enough of it is dead space
  and the volume has room. `_cleanup_logs` calls it after purging, and treats
  a host that does not recognise it as a degradation rather than a failure, so
  a newer schema against an older CLI still runs retention.

### Fixed

- The internal retention crons (`_cleanup_logs`, `_delete_expired_jwts`,
  `_delete_old_rate_limits`, `_cleanup_auth_challenges`,
  `_cleanup_cron_entries`) now delete in bounded chunks and log what they
  actually removed rather than that they queued something.

## 0.2.0

**Custom operations work for the first time.** On 0.1.1 every request to
`PATCH /db/custom/:operation` and `/db/custom/:operation/many` returned 500,
crashing in the rate-limits worker before authorization ran ([#27]).

### Breaking

- `TableRateLimits.customPolicy` now takes `String?` instead of `String`.

  Overrides declared as `customPolicy(String operation)` no longer compile —
  Dart does not allow an override to narrow a parameter type. Widen yours to
  `String?` and handle the null case:

  ```dart
  @override
  Future<RateLimitPolicy?> customPolicy(String? operation) async {
    return switch (operation) {
      'fill' => const RateLimitPolicy(maxRequests: 20, window: Duration(minutes: 1)),
      // The host could not validate the name, so every custom operation on
      // this table shares one counter.
      null => const RateLimitPolicy(maxRequests: 60, window: Duration(minutes: 1)),
      _ => .defaultPolicy,
    };
  }
  ```

  The compile error is the intended signal: there is no working behavior on
  0.1.1 to preserve, since the path 500s.

### Fixed

- `DbRateLimits` no longer asserts `request.customOperation` non-null. The host
  passes `null` on purpose whenever it cannot validate a caller-supplied
  operation name in-process — rules running in a worker rather than linked into
  the binary — so that an unvalidated name never becomes a rate-limit bucket
  dimension a caller could rotate to land on a fresh counter. The handler threw
  on exactly that value, so the documented fallback to one coarse per-table
  bucket never degraded; it crashed. `null` now means what the caller always
  said it meant.

### Upgrading

Bump the dependency **and rebuild your workers**:

```
dart pub upgrade zonai_schema
zonai compile
```

The rate-limit check runs in `db_rate_limit.exe`, which is compiled from your
project against your resolved `zonai_schema`. A stale executable keeps the old
code, and the `.protocol` stamp will not catch it — that stamp records the IPC
framing version, which did not change here.

### A note on the CLI you're running

Custom operations need this release, but the CLI has to catch up too.

zonai CLI **0.6.2 and earlier** check the resolved `zonai_schema` against the
CLI's *own* version, on the assumption that the two ship in lockstep. They
don't — so those CLIs refuse to start on any `0.x` schema, including `0.1.1`
and this release, with *"zonai_schema … is too far behind this CLI"*. Until
the next CLI release lands, pass `--no-schema-version-check`.

The next CLI replaces that comparison with a declared floor, and this version
is that floor.

[#27]: https://github.com/mrgnhnt96/zonai/issues/27

## 0.1.1

Released 2026-08-10. No changelog was kept before 0.2.0; see the git history
under `libs/zonai_schema/` for what changed.

## 0.1.0

Initial release.
