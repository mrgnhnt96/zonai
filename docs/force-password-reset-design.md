# Force password reset on sign in — design and build plan

Status: **largely built**. Written 2026-08-24. See [§12](#12-implementation-status) for what landed, what did not, and how §10's open questions were answered.

Every password in a zonai deployment today is changed by the person who owns it, on their
own initiative. `POST /auth/reset-password` mails a link; the link is confirmed at
`POST /auth/confirm`; `zonai db admin reset-password` sets one from the server box. There is
no way for an operator to say *this account must choose a new password before it is allowed
to do anything else* — no state that outlives a request, and nothing on the sign-in path
that would read it.

That gap costs three things a deployment eventually needs:

- **Temporary passwords.** `zonai db admin add --password …` and `admin reset-password` both
  mint a password that someone else chose and typed into a chat window. It stays valid
  forever.
- **Credential compromise response.** The remedy for a leaked password is "mail the user a
  reset link and hope they click it." Until they do, the leaked password still works.
- **Password policy.** Rotation, age limits, a forced change after a breach disclosure —
  all of them need the same primitive.

This adds that primitive: a **password-reset requirement**, set out of band, enforced at
password sign-in, cleared by the existing reset-confirm path.

---

## 1. What the request actually needs

| Property | Why it is not optional |
| --- | --- |
| **Durable** | The requirement must outlive the request that set it and every session that existed when it was set. A flag that lives only as long as a challenge row silently lapses when the challenge expires — and then the old password works again, which is the exact failure this exists to prevent. |
| **Not clearable by the account it constrains** | The subject of the requirement is precisely the party with a motive to remove it. |
| **Enforced before a session exists** | If the gate runs after `_createJwt`, a session was minted, recorded in `_jwt`, and handed to a caller who is under no obligation to discard it. |
| **Completable in one round trip** | An operator locked out of the last admin account, on a deployment whose SMTP is not configured, must still be able to finish. "We mailed you a link" is not a recovery path. |
| **Revoking** | Setting the requirement must kill the sessions the old password minted. Otherwise the control binds only the attacker who has *not* signed in yet. |

The last two are what rule out the two obvious implementations — "refuse the sign-in and
mail a reset link", and "let the sign-in through and enforce it in the UI".

---

## 2. The decision that shapes it

> **A gated sign-in mints no JWT. It returns a one-time password-reset ticket in a 403,
> and that ticket is an ordinary `passwordReset` auth challenge — so the entire
> "choose a new password" half of this feature is code that already exists and is
> already tested.**

`_confirmResetPassword` (`apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/reset_password.dart:95`)
already does every single thing a forced reset needs: it resolves a challenge by its
secret, rejects an expired one, refuses a password that reuses the current one
(`:159`), consumes the challenge only after everything that can still reject the
submission has run (`:179`), writes the new hash, and revokes every session the account
holds (`:208`). The forced flow needs none of that written twice. It needs the ticket
issued through a different channel — a response body instead of an email — and that is
the whole difference.

The alternative worth naming, because it is what most frameworks do, is a **restricted
session**: mint a JWT that can do nothing but change its own password. It is rejected
here for the reason `docs/api-tokens-design.md` §3 gives for a different feature — `Jwt`
is the currency of the entire authorization layer. It is what `TableRules.canList(Jwt?)`
receives, what row rules filter on, and what crosses the worker IPC boundary. A second
kind of `Jwt` that most of that layer must learn to refuse is a large, permanent surface
for a small, temporary state. A ticket that is not a credential for anything except one
endpoint adds no surface at all.

---

## 3. Where the requirement lives

A new framework-managed table, `_password_reset_requirements`:

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT PK | `Id.generate('pwr')` |
| `table` | TEXT NOT NULL | the auth collection |
| `user_id` | TEXT NOT NULL | the row id in that collection |
| `reason` | TEXT NOT NULL | `adminForced` / `temporaryPassword` / `compromised` / `passwordPolicy` |
| `created_at` | INTEGER NOT NULL | |
| `created_by` | TEXT | admin user id, or `cli` |

with `CREATE UNIQUE INDEX … ON "_password_reset_requirements" ("table", "user_id")` — one
requirement per account, so setting it twice is idempotent rather than a pile-up.

### 3.1 Why not a column on the auth table

`isVerified` is the precedent, and it is the wrong one. It is declared by the app author
(`$.isVerified('is_verified', (s) => s.isVerified)`), which means
`GetColumnNameRequest(columnName: .isVerified)` returns a **nullable** name — see
`verify_email.dart:22` guarding on it. A table that never declared the column makes the
feature a silent no-op. That is tolerable for "has this address been confirmed"; for
"this account must stop using its current password" a silent no-op is the failure mode
itself. It also means the control cannot be used on the day it is needed: it needs a
schema edit, a migration and a redeploy first.

The stronger objection is exposure. The 2026-08-15 assessment of this framework confirmed
live that the `/db` read API serializes auth-collection columns to any authorized reader —
the `$.password` Argon2 hash included — and that a single `PATCH /db` updates every
where-matched row because the generated `UPDATE` carries no `LIMIT`. A security flag
sitting in that table is a flag inside the blast radius of both findings. An internal
table is outside it: `_jwt`, `_auth_challenges` and `_oauth_identities` all live there for
the same reason, behind `InternalTableRules`/`InternalRowRules`.

### 3.2 Why not a row in `_auth_challenges`

Tempting, because it needs no migration: a new `AuthChallengeType` with a far-future
`expiresAt` and `canConsume: false`. Rejected — but for one reason, not three, and the
difference matters because the other two would not have been enough.

**The deciding reason is the cron.** `CleanupAuthChallengesCron`
(`libs/zonai_schema/lib/src/internal/crons/cleanup_auth_challenges_cron.dart`) purges
`where: Lt('expires_at', now)` with **no type filter at all**. A requirement row would
therefore need a sentinel far-future `expires_at` — a security control resting on a magic
date — or the cron would have to grow a special case for a row that is not a challenge.
Neither is a small cost: the first is silent when it goes wrong, and the second puts
knowledge of this feature into a job that has nothing else to do with it.

**The write patterns are opposites.** A challenge is consumed and then reaped by expiry;
a requirement is deleted, and only on a successful password change. One table holding
both means "why is this row still here" has two different right answers.

**`secretHash` is `TEXT NOT NULL` and a requirement has no secret** — a smell, not a
blocker. It would be satisfied with a sentinel and nobody would be misled for long.

> **Correction.** An earlier version of this section also claimed that
> `_lastChallenge`/`_expireOldChallenges` "assume every row is a live secret". **That is
> wrong.** Both filter on `type` explicitly
> (`apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/challenge.dart:34` and `:69`), so a
> new `AuthChallengeType` would be naturally isolated from them. That leg of the argument
> is removed rather than quietly softened: reuse here was more defensible than the
> original text implied, and the honest case rests on the cron alone.

The requirement and the ticket are still two different lifetimes; conflating them is the
mistake §1's first row describes. But it is worth saying that the separate table is a
judgement about one unfiltered `DELETE`, not an obvious win.

### 3.3 Cost

One indexed read per password sign-in, on `(table, user_id)`, after the password verifies.
`_validateJwt` already does a `_jwt` lookup on every authenticated request, so this is not
a new class of cost — but it is a new read on the hot path, and it will miss for
essentially every account in essentially every deployment. If that shows up in a
measurement, the fix is a process-local "are there any requirements at all" flag
invalidated on write; it is not worth building before the measurement.

---

## 4. Flows

### 4.1 Set

`ZonaiDb.requirePasswordReset({required String table, required String email, required PasswordResetReason reason, String? byUserId})`

1. Resolve the auth row. Unknown email → `StateError` (this is an admin-authenticated
   action, not a public one; there is no enumeration contract to protect here — compare
   `_resetAdminPassword`, which throws by name).
2. Refuse when the resolved table cannot authenticate with a password at all. A forced
   password reset on an OAuth-only collection is unenforceable, and failing loudly beats
   writing a row that nothing will ever read.
3. `INSERT OR REPLACE` the requirement row.
4. **`_revokeAllSessions(UnknownId(userId))`** — the same call `_confirmResetPassword:208`,
   `_logoutAll` and admin removal make. Without it the control binds only future sign-ins,
   and an attacker holding a session keeps it for up to `jwtExpiresIn` (14 days by default).

### 4.2 Clear

`ZonaiDb.clearPasswordResetRequirement({required String table, required String email})` —
deletes the row. Needed as an operator escape hatch: a requirement set on the wrong
address must be removable without that account first performing the thing it was wrongly
told to do.

### 4.3 The sign-in gate

In `_signInWithPassword` (`password.dart:44`), between the `user == null` check at `:78`
and `_createJwt` at `:83` — after the password has verified, before anything mints, records
or announces a session:

1. Look up the requirement by `(table, userId)`. Absent → fall through, nothing changes.
2. Present:
   - `_expireOldChallenges(table:, email:, type: .passwordReset)` — a fresh sign-in
     invalidates any ticket a previous one handed out, and any emailed link in flight.
   - Insert an `AuthChallenge.passwordReset` with `userId` set, `allowedAttempts: 1`, and
     `expiresAt: now + 15 minutes` — deliberately shorter than the emailed link's
     configured `expiresIn`, because the holder is at the keyboard right now.
   - Throw `PasswordResetRequiredException(token: base64('<secret>:<email>'), expiresIn:,
     reason:)`.

No JWT. No `_jwt` row. No `onSignIn` extension — the sign-in did not happen, and an
extension told otherwise would provision, log and notify against a session that does not
exist.

This one insertion point covers `POST /auth/sign-in`, `POST /auth` with `type: signIn`,
and `POST /auth/admin`: all three build a password payload and land in
`_authenticatePassword` → `_signInWithPassword`.

### 4.4 Confirm

Unchanged. `POST /auth/confirm` with `ConfirmResetPasswordAuthBody` resolves the ticket
exactly as it resolves an emailed one. Two lines are added at the end of
`_confirmResetPassword`, after the password update and the session revocation: delete the
requirement row for `(challenge.table, authRecordId)`.

Putting the clear *there* rather than in the forced path means an **emailed** reset also
satisfies a forced requirement — which is right. The requirement is "choose a new
password", not "choose it through this particular door."

`PasswordReuseException` (422) already fires when the submitted password equals the
current one. In the forced flow that is not an edge case, it is the single most likely
thing a user will try, and the existing behaviour is correct.

### 4.5 What is deliberately *not* gated

**Passwordless sign-in.** OTP, magic link, and OAuth reach `_signIntoCollection`
(`auth.dart:123`) or `_finishOAuthSignIn` and are unaffected. The requirement is a
statement about the password credential; a user who proves possession of their mailbox or
their Google account has not used the password and is not asked to. The password stays
unusable until reset either way.

**Refresh.** `_refreshToken` (`auth.dart:6`) is covered by §4.1 step 4: the requirement
cannot be set without revoking every session, so there is no live token left to refresh.
A belt-and-braces check in `_signIntoCollection` for `extensionStep == .onRefresh` costs
one read and closes the window if revocation ever regresses; recommended, not load-bearing.

**Sign-up.** A new account has no requirement.

---

## 5. The wire

### 5.1 The response

```http
403 Forbidden
{
  "error": {
    "code": "password_reset_required",
    "message": "This account must set a new password before signing in",
    "details": {
      "resetToken": "c2VjcmV0OnVzZXJAZXhhbXBsZS5jb20=",
      "expiresIn": 900,
      "reason": "temporaryPassword"
    }
  }
}
```

**403, not 401.** The entire sign-in oracle contract (`docs/auth.md`, "Failed sign-in")
rests on 401 meaning *these credentials are not valid*, rendered identically for a wrong
password and an unknown address. This response says the opposite — the credentials were
correct — so it must not share that status. 409 was considered, on the precedent of
`AdminInviteRequiresOAuthException` ("you are at the wrong door"), but this caller is at
the right door and is being refused; that is what 403 is for.

**Not a 200.** A 200 carrying no `accessToken` would be read as success by every client
written before this feature existed, which would then proceed with a null token and fail
somewhere further away. A 4xx fails closed.

### 5.2 The envelope is not the one zonai uses today

This is the part that needs deciding before anything is built.

`onAuthException` (`apps/server/routes/components/exception_catcher.dart:79`) renders
every auth failure as `{'error': '<string>'}` — a bare sentence. A sentence cannot carry a
ticket, and it cannot be branched on.

`revali_core` 3.2.0 — already in `pubspec.lock`, used nowhere in this repo — defines
`HttpError` (`lib/error/http_error.dart:27`) with exactly the shape above, and
`toEnvelope()` is its serializer. And it pays off twice, because `revali_client` 3.0.0
already understands it: `RevaliClient.request` throws `ServerException` on any non-2xx
(`revali_client.dart:171`), and `ServerException.fromBody` reads `error.code`,
`error.message` and `error.details` when the body is that envelope
(`server_exception.dart:32`), falling back to a raw body string when it is not.

So a 403 in this shape arrives in `zonai_client` as a `ServerException` with
`code == 'password_reset_required'` and `details['resetToken']` populated — **with no
change to the generated data source at all**. The generated `AuthDataSourceImpl` only ever
pattern-matches `{'data': …}` on the success path
(`libs/zonai_client/lib/gen/src/impls/auth_data_source_impl.dart`); the error path never
reaches it.

The cost: this one error speaks a different dialect from every other zonai error. Two ways
to settle it, and the choice is the reviewer's:

- **(a) Emit the structured envelope for this error only.** Nothing breaks — no client
  parses an error code that did not exist yesterday. Zonai then has two error shapes until
  someone migrates the rest.
- **(b) Migrate `onAuthException` wholesale to `HttpError`.** Consistent, gives every auth
  failure a stable branchable code, and is a **breaking wire change** for anyone reading
  `body['error']` as a string today — including `docs/auth.md`, which documents that exact
  string as part of the contract, and `tool/ci/e2e/drive.dart`, whose assertions are on
  response bodies.

Recommendation: **(a) now, (b) as its own change** with its own migration note. Do not
smuggle a wire break in behind a feature.

### 5.3 A credential in a response body

`details.resetToken` is a bearer secret. Before this ships, verify what
`authoredErrorResponse` does with an error body — specifically that it does not reach
`_log`. The redaction machinery exists (`trace_query_redaction_test.dart`); what it covers
on the *error-response* path has not been read for this design and is an open item, not an
assumption.

---

## 6. Setting it: the four producers

| Producer | Surface | Notes |
| --- | --- | --- |
| **CLI, explicit** | `zonai db admin require-password-reset <email>` / `--clear` | Alongside `apps/zonai/lib/src/commands/db/admin/reset_password.dart`. Works with no secret and no HTTP — the recovery path when everything else is locked. |
| **CLI, implicit** | `zonai db admin reset-password` | Should default to setting the requirement: someone other than the owner just chose that password. `--no-force-reset` opts out for an operator resetting their own. |
| **CLI, implicit** | `zonai db admin add --password …` | Opt-**in** (`--force-reset`), not default: the person running `add` is frequently the person who will sign in. |
| **Dashboard** | Row action on an auth collection | `POST /admin/members/:email/require-password-reset` on `AdminController` (`apps/server/routes/controllers/admin_controller.dart:34`), admin-ness enforced in the handler as the existing routes there do. UI hangs off `apps/web/lib/components/table_row_detail_panel.dart`, the same place the test-notification action landed in `9c063bf9`. |

**No new `AuthOperation` value.** Setting a requirement is an admin action authorized like
admin invites are, not an auth-flow step evaluated by `AuthRowRules`. Adding to
`enum AuthOperation { signIn, signUp, passwordReset }`
(`libs/zonai_schema/lib/src/handlers/rules/rule_request.dart:298`) would source-break every
app that switches exhaustively over it, for nothing.

**No server-side authoring API in v1.** An `AuthOperations` hook cannot set a requirement:
hooks run in the worker process and the only channel back is `MutationRequest`, which
expresses row CRUD and not framework actions. That is the same gap the custom-operation
work hit. Naming it here so the absence is a decision rather than an oversight.

---

## 7. Client and dashboard

**`zonai_client`.** `Auth.signIn` currently returns `AuthSession?` and lets exceptions out
raw (`libs/zonai_client/lib/src/auth.dart:75`). Add a translation: catch `ServerException`,
and when `code == 'password_reset_required'` rethrow a typed
`PasswordResetRequiredException(resetToken:, expiresIn:, reason:)` from `zonai_client`.
Consumers then write (elided call sites, and a type this change has not added yet, so this
fence is not compiled):

```dart no-analyze
try {
  await client.auth.signIn(body: SignInAuthBody(...));
} on PasswordResetRequiredException catch (e) {
  await client.auth.confirm(
    body: ConfirmResetPasswordAuthBody(token: e.resetToken, newPassword: chosen),
  );
  await client.auth.signIn(body: SignInAuthBody(email: email, password: chosen));
}
```

That third line is the wrinkle. `AuthHandler.verifyAuth` maps
`(ConfirmResetPasswordAuthBody(), null) => null` — confirming a reset returns **no
session**, by design, because the emailed variant is completed by whoever holds the link.
So a forced reset ends with the user signed out, holding a password they just chose.

Two options: return a session from confirm (changes the emailed path too, and mints a
session from an email link — a real security posture change, not a UX tweak), or let the
client sign in again immediately with the password it has in hand. **Recommend the
latter**, in `zonai_client`, so every consumer gets it without the server contract moving.

**Dashboard.** Its own sign-in screen must handle the 403 and route to a "choose a new
password" screen. This is the one client that cannot be left to a later release: an admin
forced to reset who cannot complete it in the dashboard has no dashboard.

---

## 8. Build order

Each step compiles and is independently reviewable.

1. **Schema.** `libs/zonai_schema/lib/src/internal/tables/password_reset_requirement_table.dart`,
   plus `InternalTableRules`/`InternalRowRules` and `TableOperations` alongside it — copy the
   shape of `oauth_identity_table.dart` and its operations/rules, which is the most recent
   table added this way.
2. **Artifacts.** `dart run tool/generate_internal_db_artifacts.dart --migrate -n
   add_password_reset_requirements`, then `--sync-migrations-dart`. Both
   `internal_db_artifacts.dart` and `internal_db_migrations.dart` are generated — do not
   hand-edit. **Do not assume the migration is `0009`**: `api_token_table.dart` is already
   authored in `internal/tables/` with no migration behind it, so the numbering depends on
   what lands first.
3. **Mutator.** `parts/auth/password_reset_requirement.dart` — set, clear, look up. Wire
   `_revokeAllSessions` into set.
4. **Gate.** The insertion in `_signInWithPassword`; the clear in `_confirmResetPassword`;
   `PasswordResetRequiredException` added to the sealed `AuthException`
   (`apps/zonai/lib/src/exceptions/auth_exception.dart:1`). The exhaustive switch in
   `onAuthException` will refuse to compile until it is handled — that is the feature.
5. **HTTP.** The 403 envelope in `onAuthException`. Swagger annotation on `signIn`,
   `authenticate` and `adminAuthenticate`.
6. **CLI.** The new command, and the default flip on `admin reset-password`.
7. **Client.** `PasswordResetRequiredException` in `zonai_client` + the re-sign-in helper.
8. **Dashboard.** Sign-in handling, then the row action.
9. **Docs.** `docs/auth.md` gains a "Forced password reset" section — and note it currently
   documents the 401 body string as contract, so §5.2's choice has to be reflected there.

---

## 9. Tests

- **Mutator unit.** Requirement set → sessions revoked. Set twice → one row. Clear → gone.
  Set on an OAuth-only table → throws.
- **Gate.** Correct password + requirement → throws, and **no `_jwt` row was written** and
  **`onSignIn` did not run**. Wrong password + requirement → the ordinary
  `InvalidPasswordOrEmailException`, indistinguishable from any other wrong password, with
  no ticket minted (a requirement must not become the enumeration oracle §1 of
  `docs/auth.md` exists to prevent).
- **Round trip.** Sign in → gated → confirm with the returned ticket → requirement gone →
  sign in with the new password → session. Then: replay the same ticket → rejected.
- **Cross-door.** Requirement set, user completes an **emailed** reset → requirement gone.
- **Passwordless.** Requirement set, OTP sign-in → succeeds and requirement survives.
- **Reuse.** Forced reset submitting the current password → 422, and the ticket is **not**
  consumed (`reset_password.dart:173` is explicit that this ordering is load-bearing).
- **e2e.** A fixture under `e2e/` driven by `tool/ci/e2e/drive.dart`, asserting the 403
  body shape — that file is where the response-body contract is actually gated. The
  compiled-binary e2e leg already dominates the CI timeout budget, so expect to raise
  `timeout-minutes` in the same change rather than discovering it in a red run.

---

## 10. Open questions

1. **§5.2 (a) or (b)** — one structured error among sentences, or migrate them all. Needs a
   decision before step 5.
2. **Does confirm return a session?** Recommended no; recommended the client re-signs in.
   If the answer is yes, the emailed reset path changes too and that needs its own review.
3. **Password age policy** — `passwordChangedAt` per account, and a requirement synthesized
   when it exceeds a configured max. The table above has no such column deliberately; it is
   a second feature that would reuse this one's enforcement. Out of scope, cheap to add
   later, worth not designing around.
4. **§5.3** — confirm the ticket cannot reach `_log` through the error-response path.

---

## 11. Adjacent findings

Two things read while designing this. Neither blocks it; both are real.

- **`_resetAdminPassword` does not revoke sessions.**
  (`apps/zonai/lib/src/db_mutator/zonai_db/parts/admin/reset_admin_password.dart:35-47`)
  It writes the new hash and returns. `_confirmResetPassword:208` revokes, with a comment
  explaining exactly why — "a reset is the remedy for a password someone else may know, so
  the sessions that password minted must not outlive it". The CLI path is the *more* likely
  compromise-response route and it is missing that. Read-verified only; not run.
- **`POST /auth/confirm` is not rate limited.** `RateLimitOperation.confirm` exists in the
  enum and is referenced nowhere in `apps/server`; the route at
  `apps/server/routes/controllers/auth_controller.dart:84` carries no `@BodyRateLimit`,
  while `sign-in`, `sign-up`, `authenticate`, `admin` and the send-* routes all do. That is
  the endpoint that verifies OTP codes, magic links and reset tokens — and the one this
  feature leans on. Worth its own fix regardless.

---

## 12. Implementation status

Written after the fact, against the code rather than against the plan above.

### Built

**Steps 1–4 (schema, artifacts, mutator, gate).** `_password_reset_requirements` with its
`InternalTableRules`/`InternalRowRules`/`TableOperations`, migration **`0010`** (not `0009`
— `api_tokens` landed first, exactly as step 2 warned), and a `kPurgeableTableNames` entry.
`ZonaiDb.requirePasswordReset` / `clearPasswordResetRequirement` /
`passwordResetRequirement` are public. The gate sits in `_signInWithPassword` before
anything mints, records or announces a session; the clear sits in `_confirmResetPassword`
after the update and the revocation, so a submission that failed an earlier check leaves
the requirement standing.

**Step 5 (HTTP).** The 403 envelope is in `onAuthException`, built through
`HttpError.forbidden(...).toEnvelope()` so the shape cannot drift. It landed **with step
4, not after it**: `AuthException` is sealed, so the exhaustive switch would not compile
without the case — the exception and its wire mapping could not be separated into two
changes. `@ApiResponse(403, …)` is on `signIn`, `authenticate` **and**
`adminAuthenticate`, because all three build a `SignInPasswordAuthPayload` and land in
`_signInWithPassword`.

**Step 6 (CLI).** `zonai db admin require-password-reset --email <a>`, with `--clear` and
`--reason`. `reset-password` now sets the requirement **by default** with
`--no-force-reset` to opt out; `admin add` gets `--force-reset` as opt-in. `--reason`
accepts kebab-case and the Dart identifier spelling, and refuses an unknown value rather
than defaulting — the value rides to the client in `details.reason`, and a fallback would
put a claim in a user-facing body that nobody made.

**Step 9 (docs).** `docs/auth.md` has a "Forced password reset" section, and it states
explicitly that this body is not shaped like the other auth errors and that a client must
branch on `error.code` rather than on `error.message`. §3.2 above is corrected.

**Step 7 (client).** `zonai_client` throws a typed `PasswordResetRequiredException` carrying
`token`, `expiresIn` and `reason`, and `completePasswordReset(…)` sits on both `Auth` and
`AdminAuth`. `reason` crosses as a **String**, not a mirrored enum: an enum would throw on a
value a newer server had added, and the client's job here is to relay what the server said,
not to ratify it.

**Step 8 (dashboard).** The sign-in form catches the exception ahead of its generic clause and
swaps itself for a forced-reset form that lands the admin **signed in** — deliberately not a
reuse of `ResetPasswordConfirmForm`, which reads its token from `?s=` and ends on a card that
offers no way onward. That ending is right for an emailed link, which reaches whoever owns the
account on any auth table and most of those are an app's users; here the caller is already at
the dashboard's own door, so the honest ending is the opposite one.

The row action and its three routes take **`?table=`** and act on the collection NAMED, not on
the `AsAdmin` one. `:email` is a path segment while `table` and `reason` are query parameters,
and that split is load-bearing: `Uri.pathSegments` percent-decodes, so `a+b@example.com`
survives a path segment, while in a query parameter `+` decodes to a space and silently
addresses a different account.

### Not built

**§9's `drive.dart` fixture is not wired in.** The `e2e/forced_password_reset` fixture
exists and is driven, but by an **in-process** suite
(`apps/zonai/test/e2e/forced_password_reset_e2e_test.dart`, 8 round trips against a
compiled project) rather than over HTTP by `tool/ci/e2e/drive.dart`. The HTTP layer needs
one thing this repo does not have yet: a hook in `tool/ci/run_e2e.sh` that runs a CLI
command between the `seed` and `verify` phases, because there is **no HTTP route that sets
a requirement** — by design — so the fixture can only be put into the gated state by the
CLI, while the server is stopped. Landing an unrun fixture in `served_fixtures` would red
the whole CI e2e leg, so it is left out rather than added untested. `timeout-minutes` was
therefore not raised either; it must be raised in the same change that adds the fixture.

### How §10's open questions were answered

1. **§5.2 → option (a).** One structured error among sentences. Migrating the rest is a
   breaking wire change and gets its own commit and its own migration note.
2. **Confirm returns no session.** The client re-signs in. The emailed reset path is
   unchanged.
3. **Password age policy** — still out of scope, still cheap to add later.
4. **§5.3 → checked, and the answer is conditional rather than flat.** Response bodies are
   never logged: `Router._authoredResponse` (revali_router 5.1.1) only logs at `>= 500`,
   and zonai logs no response body anywhere. The ONE surface that could carry the ticket
   into `_log` is `'$exception'` — `Exceptions._serverSide` interpolates an exception's
   `toString()` into a warn that the trace component persists. The 403 branch returns
   `.handled(...)` and does not call `_serverSide` at all, so nothing is logged on the
   intended path; and `PasswordResetRequiredException.toString()` carries no token,
   which is pinned by a test rather than left to a comment. That invariant is the
   mitigation, so it must not be relaxed.

Also decided, and by the operator rather than by this design: **the CLI stays admin-only, and
that is a boundary rather than a gap.** Every layer beneath it is already table-generic — the
mutator, the sign-in gate in `_signInWithPassword`, the three routes and the dashboard row
action all act on any collection carrying a password column, and `requirePasswordReset`
refuses a table with none rather than writing a row nothing would ever read. Only
`zonai db admin require-password-reset` resolves `adminPasswordTable()`, and so does its
sibling `reset-password`: the whole `zonai db admin` group is the *admin* group, and the CLI
has no non-admin account group at all. Reaching a user table from the command line would mean
either a `--table` flag on one subcommand of a namespace that promises the opposite, or a new
command group — so the dashboard is the operator surface for non-admin accounts, and the CLI
stays the no-server recovery path for admins, which is what its own help text already claims.

Also decided, and not in §10: **no new `AuthOperation` enum value.** Setting a requirement
is an admin action authorized the way admin invites are, not an auth-flow step evaluated
by `AuthRowRules`; adding to that enum would source-break every app that switches
exhaustively over it, for nothing.

### What §11 looks like now

The first adjacent finding — **`_resetAdminPassword` does not revoke sessions** — is no
longer reachable the way it was described, because `zonai db admin reset-password` now
calls `requirePasswordReset` by default and that revokes. The underlying
`_resetAdminPassword` method still does not revoke on its own, so a caller passing
`--no-force-reset`, or any future caller of the method, still gets the old behaviour. Worth
fixing at the method rather than leaving it to its callers.

The second — **`POST /auth/confirm` is not rate limited** — is unchanged, and this feature
leans on that endpoint. Still worth its own fix.

### What is proven, and by what

| Claim | Where |
| --- | --- |
| Row semantics: lookup, the unique index, collection scoping | `apps/zonai/test/src/db_mutator/zonai_db/password_reset_requirement_test.dart` |
| `toString()` never carries the ticket | `apps/zonai/test/src/exceptions/password_reset_required_exception_test.dart` |
| The 403 envelope, key-for-key, and `expiresIn` in seconds | `apps/server/test/password_reset_required_envelope_test.dart` |
| The CLI surfaces, including the `reset-password` default flip | `apps/zonai/test/src/commands/db/admin/` |
| Session revocation; the gate minting no `_jwt` row (counted, not inferred); a WRONG password against a gated account staying an ordinary 401 with no ticket minted; the round trip and its replay; reuse without burning the ticket; cross-door; passwordless; the OAuth-only refusal; clear-returns-false | `apps/zonai/test/e2e/forced_password_reset_e2e_test.dart` (compiled project, 9 tests) |
| `onSignIn` did not run on a gated attempt (§9 asks for it) | **nothing** — the gate is proven to mint no `_jwt` row, which is the half that hands a caller something; the extension not firing is still unasserted |
| The typed client exception, its `toString()` withholding the token, and the confirm round trip | `libs/zonai_client/test/password_reset_required_test.dart` (9 tests) |
| The three routes refusing a non-admin bearer, and acting on the collection `?table=` names rather than on the `AsAdmin` one | `apps/server/test/require_password_reset_admin_gate_test.dart` (19 tests) |
| The dashboard's requirement summary and reason spelling | `apps/web/test/password_reset_requirement_test.dart` (12 tests) |
| The dashboard sign-in swap and the row action **rendering** | **nothing** — both are asserted only through the pure helpers above; no component/render coverage exists in `apps/web` yet (`verify.yaml` says so under its `apps/web/lib/**` RECHECK) |
| The 403 **over the wire** | **nothing yet** — see "Not built" |
