# OAuth — design and build plan

Status: **plan**, not yet implemented. Branch: `feat/oauth`.
Companion to `docs/external-idp.md` (trusting *someone else's* JWT) — this document
covers zonai *running* the OAuth flow itself and minting its own session.

The developer experience mirrors password / OTP / magic-link exactly: **add a mixin
to the auth schema, override one member.** Everything else — routes, dashboard
tiles, provider icons, session minting — falls out of that declaration.

---

## 1. What exists today (read before changing anything)

| Concern | Where |
| --- | --- |
| Auth mixins (`PasswordAuth`, `OtpAuth`, `MagicLinkAuth`) | `libs/zonai_schema/lib/src/schemas/auth/auth.dart` |
| `AuthTable.authTypes`, `AsAdmin` | `libs/zonai_schema/lib/src/schemas/auth_table.dart` |
| `SupportedAuths`, `enum AuthType` | `libs/zonai_schema/lib/src/types/supported_auths.dart` |
| Auth flow runtime (one part file per method) | `apps/zonai/lib/src/db_mutator/zonai_db/parts/auth/` |
| Session minting (`_createJwt`, `_signIntoCollection`) | `.../parts/auth/auth.dart` |
| **External IdP verify + auto-provision** | `.../parts/auth/external_idp.dart` |
| Provisioning hook + abuse gate | `AuthExtensionRequest.onExternalAuthFirstSeen`, `externalIdpProvisioningGate` |
| One-shot secrets (OTP/magic-link/reset) | `libs/zonai_schema/lib/src/internal/tables/auth_challenge_table.dart` + `internal/crons/cleanup_auth_challenges_cron.dart` |
| Auth payloads (sealed) | `apps/zonai/lib/src/db_mutator/payloads/auth_payloads.dart` |
| HTTP surface | `apps/server/routes/controllers/auth_controller.dart` + `apps/server/lib/src/handlers/auth_handler.dart` |
| Dart client | `libs/zonai_client/lib/src/auth.dart` (+ generated `lib/gen/`) |
| Dashboard sign-in | `apps/web/lib/components/sign_in_screen.dart`, `apps/web/lib/auth/`, SSR loader `apps/web/lib/server/supported_auth_types.dart` |
| Built-in-provider precedent | `libs/zonai_schema/lib/src/config/supabase_external_idp.dart` — pure factories over a generic config |
| Env-injected secrets precedent | `apps/playground/lib/src/config/db_config.dart` (`const String.fromEnvironment(...)`) |
| JWKS verification (reusable) | `apps/zonai/lib/src/utils/jwks_idp_verifier.dart` |

**Architectural decision that shapes everything below: OAuth rides the existing
external-auth rails.** Identity resolution ends in the same
`onExternalAuthFirstSeen` extension hook and the same `externalIdpProvisioningGate`
that `external_idp.dart` uses, and session minting ends in the same `_createJwt`.
We are adding a *front end* to an auth pipeline that already exists — not a second
auth pipeline.

---

## 2. Developer-facing API

Every fence in this section is tagged `no-analyze`: it describes the API this plan
proposes, and none of those types exist yet. They become analyzable doc snippets in
`docs/oauth.md` once L1 lands — see §5.

### 2.1 The schema

```dart no-analyze
final class UserTable extends AuthTable<User>
    with PasswordAuth, OAuth, AsAdmin {
  UserTable(super.$) : /* columns as today */;

  @override
  List<OAuthProvider> get oauthProviders => [
    OAuthProvider.google(
      clientId: const String.fromEnvironment('GOOGLE_CLIENT_ID'),
      clientSecret: const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
    ),
    OAuthProvider.github(
      clientId: const String.fromEnvironment('GITHUB_CLIENT_ID'),
      clientSecret: const String.fromEnvironment('GITHUB_CLIENT_SECRET'),
    ),
    OAuthProvider.apple(
      clientId: 'com.example.app',           // Services ID
      teamId: const String.fromEnvironment('APPLE_TEAM_ID'),
      keyId: const String.fromEnvironment('APPLE_KEY_ID'),
      privateKey: const String.fromEnvironment('APPLE_PRIVATE_KEY'),
    ),
  ];
}
```

`OAuth` is a `base mixin on Auth implements HasEmail`, exactly like its siblings:

```dart no-analyze
base mixin OAuth on Auth implements HasEmail {
  /// Providers this collection can sign in with. Must be non-empty and
  /// every [OAuthProvider.id] must be unique within the list.
  List<OAuthProvider> get oauthProviders;

  @override
  @nonVirtual
  bool get supportsOAuth => true;
}
```

Adding the mixin without overriding `oauthProviders` is a **compile error** — the
member is abstract. That is the point: the declaration cannot be half-done.

### 2.2 The provider model

```dart no-analyze
sealed class OAuthProvider {
  String get id;                 // route segment + identity key: 'google'
  String get displayName;        // 'Google'
  OAuthBrand get brand;          // icon + colors for the dashboard
  OAuthEndpoints get endpoints;  // authorize / token / userinfo / jwks / issuer
  List<String> get scopes;
  OAuthClaimMap get claims;      // subject/email/emailVerified/name/picture paths
  bool get usesPkce;
  OAuthLinking get linking;      // byVerifiedEmail (default) | never | always
}
```

Two concrete shapes:

- `BuiltInOAuthProvider` — produced only by the named factories below. Endpoints,
  scopes, claim map and brand are baked in; the developer supplies credentials and
  may override `scopes` / `linking`.
- `CustomOAuthProvider` — `OAuthProvider.custom(...)`, every field explicit. This is
  the "roll your own" escape hatch and must be able to express any OAuth2 /
  OIDC provider without a code change to zonai.

```dart no-analyze
OAuthProvider.custom(
  id: 'acme',
  displayName: 'Acme SSO',
  brand: OAuthBrand(
    icon: OAuthIcon.url('/images/acme.svg'),   // or OAuthIcon.svg('<svg …>')
    background: '#101828',
    foreground: '#FFFFFF',
  ),
  endpoints: OAuthEndpoints(
    authorization: 'https://sso.acme.com/authorize',
    token: 'https://sso.acme.com/token',
    userInfo: 'https://sso.acme.com/userinfo',
    issuer: 'https://sso.acme.com',            // enables id_token verification
    jwks: 'https://sso.acme.com/.well-known/jwks.json',
  ),
  scopes: ['openid', 'email', 'profile'],
  claims: OAuthClaimMap(subject: 'sub', email: 'email', name: 'name'),
  clientId: ..., clientSecret: ...,
)
```

### 2.3 Built-in providers

Required: **Apple, Google, GitHub**. Shipping alongside them because they are the
next most-asked-for and cost only a factory + an icon each:

`google`, `apple`, `github`, `microsoft`, `facebook`, `discord`, `gitlab`, `linkedin`.

Each factory is **pure** — it returns a `BuiltInOAuthProvider` with no network and
no runtime, exactly as `SupabaseExternalIdp` does today. Two carry provider-specific
behaviour that must be implemented, not hand-waved:

- **Apple** — `client_secret` is not a static string. It is an ES256 JWT signed with
  the developer's `.p8` key, `iss=teamId`, `kid=keyId`, `sub=clientId`,
  `aud=https://appleid.apple.com`, max 6-month expiry. It must be generated per
  token request (cache until near expiry). Apple also returns the user's name
  **only on the first authorization**, in a form-post `user` field, and its email
  may be a private-relay address.
- **GitHub** — not OIDC. No `id_token`; `GET /user` may return `email: null`, so the
  primary verified address must be fetched from `GET /user/emails`.

### 2.4 What the dashboard receives

The dashboard and the Dart client must **never** see `clientSecret`, Apple private
keys, or token endpoints. `OAuthProvider.toPublic()` yields:

```dart no-analyze
final class OAuthProviderPublic {
  final String id;              // 'google'
  final String displayName;     // 'Google'
  final String table;           // auth collection this provider belongs to
  final OAuthProviderKind kind; // google|apple|github|…|custom — picks the bundled icon
  final String? iconUrl;        // custom providers only
  final String? iconSvg;        // custom providers only
  final String? background;
  final String? foreground;
  final String startPath;       // '/auth/oauth/start/google?table=users'
}
```

This redaction is a **review gate**, not a nicety: a test must assert that no
serialized public payload contains any secret field.

---

## 3. Flows

### 3.1 Server-driven redirect flow (admin dashboard, web apps)

1. `GET /auth/oauth/start/:provider?table=&redirect_to=`
   - resolve provider from the table's `oauthProviders`
   - generate `state` (random) + PKCE `code_verifier` + OIDC `nonce`
   - persist one `_auth_challenges` row: `type: oauthState`, `secretHash: sha256(state)`,
     `target: provider id`, `table:` auth table, `expiresAt: now + 10m`,
     `allowedAttempts: 1`, `metadata: {verifier, nonce, redirectTo}`
   - 302 to the provider's authorization URL, `redirect_uri` = `{baseUrl}/auth/oauth/callback/:provider`
2. `GET /auth/oauth/callback/:provider?code&state`
   - consume the challenge (single-use, unexpired) — reuse the existing consume
     semantics from `challenge.dart`
   - exchange `code` at the token endpoint with `code_verifier` + client secret
     (Apple: freshly signed JWT secret)
   - if OIDC: verify `id_token` via `JwksIdpVerifier` — signature, `iss`, `aud`,
     `exp`, `nonce`. Otherwise: call `userInfo` with the access token
   - resolve identity (§3.3), mint the session with `_createJwt`
   - redirect to `redirect_to`; for the dashboard, set the `ZonaiCookie.authToken`
     cookie exactly as password sign-in does

### 3.2 Native / public-client flow (Flutter apps via `zonai_client`)

Mobile apps run the provider SDK themselves (`google_sign_in`, Sign in with Apple)
and hand zonai the result:

`POST /auth/oauth` with either `{table, provider, idToken}` or
`{table, provider, code, codeVerifier, redirectUri}` → `{accessToken, user}`.

Same verification and identity resolution as §3.1; no challenge row, because the
client owns the state. **This is the primary path for zonai's Dart consumers** —
do not treat it as an afterthought behind the web flow.

### 3.3 Identity resolution

New internal table `_oauth_identities`:
`id`, `table`, `user_id`, `provider`, `subject`, `email`, `created_at`, `last_login_at`,
unique on `(table, provider, subject)`.

1. `(table, provider, subject)` hit → load that user row → sign in. Done.
2. Miss, and the provider asserts a **verified** email matching an existing row in
   the auth table → link: insert the identity row, sign in.
   Governed by `OAuthLinking`: `byVerifiedEmail` (default), `never`, `always`.
   `always` is an account-takeover footgun and must be documented as such.
3. Still nothing → provision: `externalIdpProvisioningGate.canProvision(...)`, then
   `AuthExtensionRequest.onExternalAuthFirstSeen` under a `ProvisioningJwt`, then
   insert the identity row. **Same hook as external IdP** — one provisioning story
   for the developer.

### 3.4 Sessions

`_createJwt` unchanged. Refresh, `logout`, `logoutAll`, `jwtExpiresIn`, per-table
JWT config and the `_jwt` revocation table therefore all work for OAuth sessions
with no extra code.

---

## 4. Non-negotiable security requirements

These are the acceptance criteria for the review leaf; each needs a test.

1. `state` is random ≥128 bits, stored hashed, single-use, ≤10 min TTL.
2. PKCE S256 on every provider that supports it; `code_verifier` never leaves the server in the redirect flow.
3. OIDC `id_token`: verify signature via JWKS, plus `iss`, `aud`, `exp`, `nonce`.
4. `redirect_uri` is derived from `baseUrl` and exact-matched — never taken from the request.
5. `redirect_to` must be a relative path or an allowlisted origin. Open-redirect rejection is a test, not a comment.
6. Account linking by email requires `email_verified == true` from the provider.
7. Secrets, codes, tokens and `state` never reach the logger, error messages, or the swagger surface.
8. `RateLimitOperation.oauthStart` / `.oauthCallback` exist and are enforced.
9. `toPublic()` leaks nothing — asserted by test.
10. A provider with an empty `clientId`/`clientSecret` fails at boot with a clear message, not on first sign-in.

---

## 5. Build plan — leaves and waves

Every leaf below lists the files it **owns**. No two leaves in the same wave own the
same file. A leaf is done when the repo analyzes clean and its own tests pass.

### Wave 0 — types and mixin (blocking, single crawler)

**L1 · `oauth-schema-types`**
Owns `libs/zonai_schema/lib/src/types/supported_auths.dart`,
`libs/zonai_schema/lib/src/schemas/auth/auth.dart`,
`libs/zonai_schema/lib/src/schemas/auth_table.dart`,
new `libs/zonai_schema/lib/src/types/oauth/**`, the `zonai_schema` export barrels.

- `AuthType.oauth`; `SupportedAuths.supportsOAuth`; `AuthTable.authTypes` includes it
- `OAuth` mixin with abstract `oauthProviders`
- `OAuthProvider` sealed model, `OAuthEndpoints`, `OAuthClaimMap`, `OAuthBrand`,
  `OAuthIcon`, `OAuthLinking`, `OAuthProviderKind`, `OAuthProviderPublic` + `toPublic()`
- the 8 built-in factories (pure; endpoints/scopes/claim maps only — no HTTP yet)
- validation: unique ids, non-empty credentials, non-empty list
- **repair every exhaustive `switch (AuthType)` in the repo** so the tree compiles
  again (`apps/web/lib/components/sign_in_screen.dart`, `apps/web/lib/auth/auth_routes.dart`,
  `apps/zonai/lib/src/commands/dev/components/dev_schema_form.dart`, `apps/zonai/lib/src/commands/db/test.dart`, …).
  Minimal, honest branches — real UI arrives in L7.
- unit tests for the model + `toPublic()` redaction

### Wave 1 — three parallel crawlers

**L2 · `oauth-identity-store`**
Owns `libs/zonai_schema/lib/src/internal/tables/**`, `internal/crons/**`,
`apps/zonai/tool/generate_internal_db_artifacts.dart` output + the new migration.
- `_oauth_identities` table (§3.3) + `AuthChallengeType.oauthState`
- regenerate internal DB artifacts and add the migration (`sip run schema gen …`)
- confirm the existing cleanup cron sweeps `oauthState` challenges

**L3 · `oauth-provider-runtime`**
Owns `apps/zonai/lib/src/utils/oauth/**`.
- authorization-URL builder, PKCE (S256), state/nonce generation
- token-exchange + userinfo client (injectable HTTP client so tests need no network)
- **Apple ES256 client-secret signer** (spike first: confirm what the repo can sign
  with today — `jwks_idp_verifier.dart` *verifies*; signing may need a dependency.
  Report the finding before adding one.)
- GitHub `/user/emails` primary-verified fallback
- claim extraction via `OAuthClaimMap`
- all pure/unit-testable against recorded fixtures

**L4 · `oauth-dashboard-assets`**
Owns `apps/web/lib/components/theme/oauth_*.dart` and any new asset files.
- one hand-authored inline SVG per built-in kind (official brand marks, embedded —
  **no CDN**, the dashboard must render offline)
- light/dark handling (GitHub and Apple marks invert)
- `OAuthProviderIcon` component: bundled kind → `iconSvg` → `iconUrl` → letter-tile
  fallback (mirroring the `brand_logo.dart` letter tile)
- `OAuthProviderButton` using `background`/`foreground`
- widget tests for each fallback rung

### Wave 2 — runtime (single crawler; wave 3 depends on its contracts)

**L5 · `oauth-db-mutator`**
Owns `apps/zonai/lib/src/db_mutator/**` (new `parts/auth/oauth.dart`, `payloads/auth_payloads.dart`).
- `StartOAuthAuthPayload`, `CompleteOAuthAuthPayload`, `NativeOAuthAuthPayload`
- start / callback / native flows per §3.1–3.2
- identity resolution + linking + provisioning through the existing hook and gate
- an operation exposing `OAuthProviderPublic` per table (sibling of
  `GetAdminTablesOperationRequest`) so dashboard and client can list providers
- `_adminCollectionFor(AuthType.oauth)` works for `AsAdmin` tables
- tests with a stub provider — no live network

### Wave 3 — surfaces (three parallel crawlers)

**L6 · `oauth-http-surface`** — owns `apps/server/**`
routes (`GET start/:provider`, `GET callback/:provider`, `GET providers`, `POST /auth/oauth`),
handler methods, request bodies, `RateLimitOperation.oauthStart`/`.oauthCallback`,
swagger regen. Confirm revali's path-param syntax before writing routes; see
`docs/revali-dot-shorthand-codegen.md` for the annotation trap.

**L7 · `oauth-dashboard-wiring`** — owns `apps/web/lib/**` except `components/theme/oauth_*`
SSR `loadOAuthProviders()` sibling of `loadSupportedAuthTypes()`, `oauthProvidersProvider`,
provider tiles on `AuthTypePickerScreen`, callback route + cookie handoff,
`AuthRoutes` entries, back-navigation for the oauth type.

**L8 · `oauth-dart-client`** — owns `libs/zonai_client/**`
`client.auth.oauth.providers()`, `.startUrl(...)`, `.complete(...)`, `.signInWithIdToken(...)`;
regenerate via `sip run client gen`.

### Wave 4 — proof and documentation (two parallel crawlers)

**L9 · `oauth-e2e`** — owns `e2e/oauth/**`
Model on `e2e/external_auth`. A stub provider server (authorize → code → token →
userinfo) exercising: first-seen provisioning, returning sign-in, verified-email
linking, unverified-email link **rejection**, replayed `state` rejection, expired
`state` rejection, open-redirect rejection, GitHub null-email path.

**L10 · `oauth-docs`** — owns `docs/oauth.md`, `apps/docs/content/authentication/oauth.md`,
`apps/docs/lib/src/navigation.dart`, search index / sitemap, `apps/playground/lib/src/schemas/users.dart`
Per-provider setup walkthroughs (callback URL, console steps, required env vars) for
all 8 built-ins plus the custom recipe. Every code fence must analyze — see
`docs/doc-snippet-drift-fix-plan.md`. Playground gains a real `OAuth` declaration.

### Wave 5 — gate (single crawler)

**L11 · `oauth-verify`**
Full `sip run analyze` + `sip run test` + e2e; walk §4 item by item and produce a
pass/fail table with the test that proves each; run the playground and drive a real
sign-in against the stub provider. Report unfinished items rather than closing over them.

---

## 6. Known risks

| Risk | Handling |
| --- | --- |
| Apple ES256 signing may need a new dependency | L3 spikes it first and reports before adding one |
| `AuthType.oauth` breaks exhaustive switches in **user** code | Breaking change — note it for the release; L1 documents it |
| Provider brand assets are trademarks | Use official marks, unmodified, per each provider's brand guidelines; no recoloring |
| Revali path params in a nested controller route | L6 confirms syntax against a working route before building on it |
| Internal-table migration must round-trip on existing DBs | L2 tests migration on a populated fixture DB |
| Secrets sitting in schema source | Documented pattern is `const String.fromEnvironment`; L10 shows only that form |
