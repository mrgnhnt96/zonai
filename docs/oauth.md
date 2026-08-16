# OAuth — internal reference

Zonai can run the OAuth2/OIDC dance itself and mint its own session, as an
alternative to [`docs/external-idp.md`](external-idp.md) (trusting a token
someone else's IdP already signed). This is the internal map of how that
works: the flows, the identity table, where each piece lives, and the test
that proves each security property in the original design's §4.

The developer-facing API — the `OAuth` mixin, the built-in provider
factories, per-provider console walkthroughs — is documented on the public
site at [`apps/docs/content/authentication/oauth.md`](../apps/docs/content/authentication/oauth.md).
This page is the "how it's built" companion, not a second copy of "how to use
it."

Design history: [`docs/oauth-design.md`](oauth-design.md). Everything below
describes what actually landed, which in a few places is narrower than that
plan proposed — noted inline.

## Where each piece lives

| Concern | Where |
| --- | --- |
| `OAuth` mixin, `validateOAuthProviders` | `libs/zonai_schema/lib/src/schemas/auth/auth.dart` |
| `OAuthProvider` sealed model + 8 built-in factories + `.custom(...)` | `libs/zonai_schema/lib/src/types/oauth/oauth_provider.dart` |
| `OAuthEndpoints`, `OAuthClaimMap`, `OAuthBrand`, `OAuthIcon`, `OAuthLinking`, `OAuthProviderKind`, `OAuthProviderPublic` | `libs/zonai_schema/lib/src/types/oauth/` |
| `_oauth_identities` internal table | `libs/zonai_schema/lib/src/internal/tables/oauth_identity_table.dart` |
| `AuthChallengeType.oauthState` (the `state` challenge row) | `libs/zonai_schema/lib/src/internal/tables/auth_challenge_table.dart` |
| Auth payloads (`StartOAuthAuthPayload`, `CompleteOAuthAuthPayload`, `NativeOAuthAuthPayload`) | `apps/zonai/lib/src/db_mutator/payloads/auth_payloads.dart` |
| Flow runtime (`oauthProviders`, `startOAuth`, `startAdminOAuth`, `completeOAuth`, the native path) | `apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/oauth.dart`, wired into `ZonaiDb` in `zonai_db.dart` |
| PKCE, authorization-URL building, token exchange, userinfo, id_token verification | `apps/zonai/lib/src/utils/oauth/` |
| Apple ES256 client-secret signing | `apps/zonai/lib/src/utils/oauth/apple_client_secret_signer.dart` |
| GitHub's null-email fallback (`GET /user/emails`) | `apps/zonai/lib/src/utils/oauth/github_email_resolver.dart` |
| OAuth-specific exceptions | `apps/zonai/lib/src/exceptions/auth_exception.dart` (`OAuthProviderNotFoundException`, `OAuthRedirectNotAllowedException`) — mapped to HTTP in `apps/server/routes/components/exception_catcher.dart` |
| Provisioning hook + abuse gate | Same hook and gate `external_idp.dart` uses — `AuthExtensionRequest.onExternalAuthFirstSeen`, `externalIdpProvisioningGate`. OAuth adds no second hook. |
| Session minting | Same `_createJwt` every other auth method uses. No OAuth-specific token code. |
| Dashboard provider icons/buttons | `apps/web/lib/components/theme/oauth_icon.dart`, `oauth_button.dart`, `oauth_marks.dart`, `oauth_sanitize.dart` |
| End-to-end proof | `apps/zonai/test/e2e/oauth_e2e_test.dart` + `apps/zonai/test/support/oauth_stub_server.dart` |

## The schema layer

A table opts in with `with OAuth` and overrides one abstract member:

```
final class UserTable extends AuthTable<User> with OAuth, AsAdmin {
  @override
  List<OAuthProvider> get oauthProviders => [ ... ];
}
```

`OAuthProvider` is `sealed` into two shapes: `BuiltInOAuthProvider` (produced
only by the eight named factories — `.google`, `.apple`, `.github`,
`.microsoft`, `.facebook`, `.discord`, `.gitlab`, `.linkedin`) and
`CustomOAuthProvider` (`OAuthProvider.custom(...)`, every field explicit).
Full walkthroughs, scopes and env-var conventions for each are on the public
page linked above.

`oauth.validateOAuthProviders()` — empty list or a duplicate `id` throws a
`StateError` — runs every time a table's providers are listed
(`db_operations.dart`'s `_getOAuthProviders`), not lazily on first sign-in.
See §4 item 10 below.

## Flows

### Server-driven redirect flow (`ZonaiDb.startOAuth` / `.completeOAuth`)

1. **Start.** Resolve the provider from the table's `oauthProviders`, generate
   `state` (random) + a PKCE `code_verifier` (providers that support PKCE) +
   an OIDC `nonce`, and persist one `_auth_challenges` row: `type: oauthState`,
   `secretHash: sha256(state)`, `target: provider id`, `table:` the auth
   table, `expiresAt: now + 10m`, `allowedAttempts: 1`, `metadata: {verifier,
   nonce, redirectTo}`. Returns the provider's authorization URL, built with
   `redirect_uri = {baseUrl}/auth/oauth/callback/:provider`.
2. **Callback.** Consume the challenge (single-use, unexpired — the same
   consume semantics `challenge.dart` uses elsewhere), exchange `code` at the
   token endpoint with `code_verifier` plus the client secret (Apple: a
   freshly signed ES256 JWT). If the provider is a verifiable OIDC issuer
   (`OAuthEndpoints.issuer` + `.jwks` both set), verify `id_token` via
   `JwksIdpVerifier` — signature, `iss`, `aud`, `exp`, `nonce`. Otherwise call
   `userInfo` with the access token. Resolve identity (below), mint the
   session with the same `_createJwt` every other auth method uses.

`startAdminOAuth` is the `AsAdmin` counterpart: it resolves the `AsAdmin`
table configured for `AuthType.oauth` the same way `_adminCollectionFor`
already did for every other auth type — no new admin-resolution code was
needed.

### Native / public-client flow (`ZonaiDb`'s native path)

For an app that already ran the provider's own SDK (`google_sign_in`, Sign in
with Apple) and holds the result: either an `idToken` (OIDC providers) or a
`code` + `codeVerifier` + `redirectUri` the app itself generated and
exchanged against. Same identity resolution and session minting as the
redirect flow; no `_auth_challenges` row, because the client already owns
`state`/PKCE. Admin native sign-in never auto-provisions — see the security
table below.

### Identity resolution

Every resolution starts against `_oauth_identities`, keyed unique on
`(table, provider, subject)`:

1. **Hit** → load that user row → sign in.
2. **Miss, provider asserts a verified email matching an existing row** → link:
   insert the identity row, sign in. Governed by `OAuthLinking`:
   - `byVerifiedEmail` (default) — only when the provider's `emailVerified`
     claim is `true`.
   - `never` — an unrecognized subject always falls through to provisioning
     (or rejection), regardless of email.
   - `always` — links on email match even when the provider does not assert
     it verified. Documented on `OAuthLinking.always` itself as an
     account-takeover footgun: anyone who controls an email address can sign
     in as the row that owns it without proving they control the inbox.
3. **Still nothing** → `externalIdpProvisioningGate.canProvision(...)`, then
   `AuthExtensionRequest.onExternalAuthFirstSeen` under a `ProvisioningJwt`,
   then insert the identity row. **This is the same hook `external_idp.dart`
   uses** — an app that already wired up external-IdP provisioning needs no
   OAuth-specific extension code at all (see
   `e2e/oauth/lib/src/extensions/users_extensions.dart`, whose
   `onExternalAuthFirstSeen` is a five-line map from claims to columns).

## The identity table

`_oauth_identities` (`OAuthIdentityTable`):

| Column | Notes |
| --- | --- |
| `id` | `OAuthIdentityId`, suffix `oid` |
| `table` | The auth collection's name, e.g. `'users'` |
| `user_id` | The row this identity signs in as. **Not a real SQL foreign key** — `table` names an app-defined schema chosen dynamically, which this layer can't express as a FK (same pre-existing gap as `_jwt.user_id`). A deleted user leaves an orphaned identity row; there is no sweep for it yet. |
| `provider` | `OAuthProvider.id`, e.g. `'google'` |
| `subject` | The provider's `sub` claim (or GitHub's numeric user id) |
| `email` | The provider's email claim at last sign-in — nullable, not every provider/scope returns one |
| `created_at`, `last_login_at` | |

Unique index `oauth_identities_lookup_unique` on `(table, provider,
subject)` — the lookup key identity resolution's step 1 hits.

## Security properties (§4) and what proves each

| # | Requirement | Test |
| --- | --- | --- |
| 1 | `state` random ≥128 bits, stored hashed, single-use, ≤10 min TTL | `'startOAuth mints a single-use PKCE challenge and returns an ...'`, `'a replayed state is rejected'`, `'an expired state is rejected'` |
| 2 | PKCE S256 on every provider that supports it; `code_verifier` never leaves the server in the redirect flow | Same `startOAuth`/callback tests above — the verifier is stored server-side in `_auth_challenges.metadata`, never returned to the client |
| 3 | OIDC `id_token`: verify signature via JWKS, plus `iss`, `aud`, `exp`, `nonce` | `'native flow: an idToken payload routes to id_token verification, ...'` |
| 4 | `redirect_uri` derived from `baseUrl`, exact-matched, never taken from the request | Callback builds `redirect_uri` from `AppConfig.baseUrl` server-side; not a request field on `CompleteOAuthAuthPayload` at all |
| 5 | `redirect_to` must be relative or an allowlisted origin — open-redirect rejection is a test | `'startOAuth rejects an open-redirect redirect_to'` (`OAuthRedirectNotAllowedException`) |
| 6 | Account linking by email requires `email_verified == true` | `'byVerifiedEmail linking connects a new subject to an existing row ...'`, `'byVerifiedEmail rejects linking an unverified email -- provisions a ...'`, `'OAuthLinking.always links even an unverified email -- the ...'` |
| 7 | Secrets, codes, tokens and `state` never reach the logger, error messages or the swagger surface | Not covered by a dedicated OAuth test yet — inherited from the same request/error pipeline external-idp and password auth already run through. Worth a direct assertion once the HTTP surface (below) lands. |
| 8 | `RateLimitOperation.oauthStart` / `.oauthCallback` exist and are enforced | Both are declared in `libs/zonai_schema/lib/src/types/rate_limit_operation.dart` and applied by `apps/server/routes/components/oauth_rate_limit.dart` on every `/auth/oauth/*` route |
| 9 | `toPublic()` leaks nothing | `'oauthProviders lists every provider, redacted -- no secret ever ...'` |
| 10 | A provider with empty `clientId`/`clientSecret` fails at boot, not on first sign-in | Each built-in factory calls `_requireNonEmpty` at construction (`ArgumentError`); `validateOAuthProviders()` (empty list / duplicate id) runs on every `_getOAuthProviders` call — see `libs/zonai_schema/test/src/schemas/auth/oauth_test.dart` |

Admin-specific coverage beyond the numbered list: `'adminSupportedAuthTypes
includes oauth'`, `'startAdminOAuth resolves the AsAdmin+OAuth table, and its
callback ...'`, `'native admin sign-in never auto-provisions'` — an admin
table's first-seen native sign-in is rejected rather than silently creating
an admin row.

**Admin invites are the one exception, and they are narrow.** An accepted
invite is the authorization that lifts that refusal, for the invited address
only: `_provisionInvitedAdmin` (`oauth.dart`) creates the row only when the
provider's email is verified and equals the invite's target
case-insensitively, and a mismatch leaves the invite unconsumed rather than
burning it. Everything else about admin OAuth still refuses to provision.
See [`docs/admin-invite-design.md`](admin-invite-design.md).

One gap the runtime author disclosed rather than papered over remains:
live-network OIDC `id_token` verification isn't exercised end-to-end, because
`JwksIdpVerifier` rightly demands `https` and a local stub server could only
pass by weakening that check. It is unit-tested instead, via the OIDC stub
provider.

The second disclosed gap — GitHub's null-email branch — is closed. It was
never really "unreachable from a stub"; it was unreachable *at all*, because
the resolver was constructed inline at the call site with no seam, so nothing
could substitute it. `github_null_email_fallback_test.dart` now covers the
branch with the transport faked, and
`github_null_email_fallback_live_test.dart` covers it against the real
`api.github.com`. Both fail when the branch is removed — checked by removing
it, not assumed.

## Implementation status

As of this page, landed and tested:

- The schema layer — `OAuth` mixin, all 8 built-in factories, `.custom(...)`,
  `toPublic()` redaction (Wave 0/L1).
- `_oauth_identities` + `oauthState` challenge type (Wave 1/L2).
- PKCE, authorization-URL building, token exchange, userinfo, Apple ES256
  signing, GitHub's email fallback (Wave 1/L3).
- Dashboard provider icons and the sign-in button component (Wave 1/L4).
- The full flow runtime on `ZonaiDb` — `startOAuth`, `startAdminOAuth`,
  `completeOAuth`, the native path, identity resolution, linking,
  provisioning — plus the 20-case e2e suite (Wave 2/L5).
- **HTTP routes** (Wave 3). `AuthController` serves `oauth/providers`,
  `oauth/start/:provider`, `oauth/callback/:provider`, the native path, and
  the two admin entrypoints `admin/oauth/start/:provider` and
  `admin/invite/oauth/start/:provider`. `RateLimitOperation.oauthStart` and
  `.oauthCallback` are declared and applied — §4 item 8 above is closed.
- **Dashboard wiring** (Wave 3). `auth_router.dart` renders
  `OAuthSignInScreen` for `AuthType.oauth`; the `UnimplementedError` this
  section used to describe is gone.
- **`zonai_client` bindings** (Wave 3). `Auth.providers`, `.startUrl`,
  `.complete` and `.signInWithIdToken` wrap the redirect and native flows.

**Still open:** nothing.

**Closed since:**

- **A live server's log output is now inspected for the OAuth `code`,
  `state` and client secret.** §4 item 7's chain ends here:
  `trace_query_redaction_test.dart` proves the redaction *function*,
  `oauth_routes_test.dart` and `oauth_e2e_test.dart` prove the response
  *surfaces*, and `admin_invite_http_oauth_e2e_test.dart` now proves what the
  process, at `Logger(level: .verbose)`, actually wrote.

  **This section's own premise was wrong, and the error is worth recording.**
  It claimed the admin-invite suite "does exactly that
  (`_LiveServer.capturedLogOutput`)" and that closing the item meant giving
  the OAuth e2e a live server. In fact the admin-invite suite has driven a
  real OAuth start→callback over a live server all along — what it did not
  have was a working log capture. `TraceId` re-overrides `loggerProvider` for
  the duration of every request with `Logger.print(...)`, which writes through
  `PrintSink` → Dart's `print`, discarding the `IOSink` the harness injected.
  `capturedLogOutput` therefore only ever held the startup lines emitted
  before the first request: 178 bytes of config-executable chatter, against
  which every `isNot(contains(...))` passed for free. The pre-existing
  "the raw invite token never reaches the server process log output" test had
  been vacuous since the day it was written.

  The fix is to capture the *zone* rather than the sink, since `print` is
  zone-scoped. With that in place, disabling `redactSensitiveQuery` turns both
  log tests red — the new one on the OAuth `code`/`state`, and the invite-token
  one that previously could not fail. That control is the only reason either
  is worth anything, and it is why the new test also asserts the buffer is
  non-empty and that an exchange was actually recorded: an empty buffer is
  precisely how this failed before.

- **Live-network JWKS verification.** This section used to argue it was best
  left documented, because an honest test needs a real issuer or a trusted TLS
  certificate and the alternative is lowering the `https` check the verifier
  exists to enforce. The `live` tag added for the GitHub fallback removed that
  objection: `jwks_idp_verifier_live_test.dart` verifies a genuine
  Google-signed `id_token` — minted by `gcloud auth print-identity-token`,
  `iss: https://accounts.google.com`, the exact issuer `OAuthProvider.google`
  declares — against Google's live JWKS over real TLS, through the production
  `oauthJwksConfig` helper. No `https` check was lowered.

  The case a mock can never make: `_refreshCache` skips key entries `jose`
  cannot parse, and that `continue` is silent. A test that authors its own
  JWKS only ever writes shapes `jose` just produced, so an issuer publishing
  something `jose` rejected would empty the key store and fail every sign-in
  with a bare `InvalidJwtException`. The live test asserts every key Google
  actually publishes parses.

  Two negative controls keep it honest — a wrong `aud` and a one-character
  signature flip must both be rejected — and disabling the signature check
  turns exactly one test red, which is how the credential leak described in
  the file's `outcomeOf` helper was found and closed.

The route paths and payload shapes were fixed before the routes existed —
`OAuthProviderPublic.startPath` bakes in `/auth/oauth/start/:id?table=:table`,
and `OAuthProviderNotFoundException`'s message cites
`/auth/oauth/start/:provider` — so the public docs page and the server now
describe the same contract.

## See also

- [`docs/external-idp.md`](external-idp.md) — the alternative: trust JWTs an
  existing IdP already issues, instead of zonai running the OAuth flow.
- [`docs/oauth-design.md`](oauth-design.md) — the original design and build
  plan this page and the implementation both trace back to.
- [Authentication → OAuth](../apps/docs/content/authentication/oauth.md) —
  the developer-facing page: the mixin, provider walkthroughs, custom
  providers, account linking.
- [`docs/admin-invite-design.md`](admin-invite-design.md) — how someone is
  added to an admin table whose only sign-in method they do not control yet,
  and the one case where an OAuth callback may provision an admin row.
