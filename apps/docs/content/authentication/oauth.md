---
title: OAuth
description: Sign in with Google, Apple, GitHub and other providers — zonai runs the OAuth2/OIDC flow itself and mints its own session.
---

OAuth lets users sign in with an identity provider — Google, Apple, GitHub and
five others out of the box, or any OAuth2/OIDC provider via a custom
declaration. Zonai runs the whole flow itself: authorization redirect, code
exchange, `id_token`/userinfo verification, and session minting. The result
is a normal zonai JWT — same refresh, same revocation, same `Jwt` your rules
and extensions already see for password, OTP and magic-link sign-in.

The developer experience matches those three exactly: **add a mixin to your
auth schema, override one member.**

<Info>

Zonai *running* OAuth is not the same thing as zonai *trusting* an OAuth
provider's token. If you already have Supabase Auth, Auth0, Clerk or another
IdP issuing JWTs and just want zonai to accept them, see [External Identity
Providers](/authentication/external-idp) instead — no redirect flow, no
provider console setup, just a JWKS or shared-secret config. Reach for this
page when you want zonai itself to own the OAuth handshake; reach for that
one when someone else already does.

</Info>

## Enabling OAuth

Add `with OAuth` to your auth table class and override `oauthProviders`:

```dart no-analyze
final class UserTable extends AuthTable<User>
    with OAuth, AsAdmin {
  // ...

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
  ];
}

final users = authTable('users', UserTable.new);
```

`oauthProviders` is abstract — leaving it unimplemented is a compile error,
not a runtime surprise. The list must be non-empty and every
`OAuthProvider.id` must be unique; both are checked the moment providers are
listed (table registration), not on a user's first sign-in attempt. `OAuth`
can combine with `PasswordAuth`, `OtpAuth` and `MagicLinkAuth` on the same
table — see [Auth Tables](/schemas/auth-tables) for the full mixin list and
column setup, and [Environment Variables](/configuration/environment-variables)
for how `.env` and `String.fromEnvironment` fit together. The `const` is
load-bearing there too — without it you get the runtime default (`''`)
instead of the value baked in at compile time.

Each provider is one of two shapes:

- **Built-in** — produced only by the eight named factories below
  (`OAuthProvider.google(...)`, etc). Endpoints, scopes and claim mapping are
  baked in from that provider's own OIDC discovery document or API reference;
  you supply credentials and may override `scopes` and `linking`.
- **Custom** (`OAuthProvider.custom(...)`) — every field explicit. Use this
  for anything without a named factory: an internal SSO provider, a
  self-managed GitLab instance, any OAuth2/OIDC issuer.

## Built-in providers

| Provider | Factory | PKCE | OIDC (`id_token`) |
| --- | --- | --- | --- |
| Google | `OAuthProvider.google` | yes | yes |
| Apple | `OAuthProvider.apple` | no ([Apple's flow doesn't support it](#apple)) | yes |
| GitHub | `OAuthProvider.github` | yes | no — userinfo only |
| Microsoft | `OAuthProvider.microsoft` | yes | yes |
| Facebook | `OAuthProvider.facebook` | no | no — Graph API `/me` only |
| Discord | `OAuthProvider.discord` | yes | no — userinfo only |
| GitLab | `OAuthProvider.gitlab` | yes | yes |
| LinkedIn | `OAuthProvider.linkedin` | yes | yes |

Every walkthrough below assumes the redirect flow's callback URL:

```
{baseUrl}/auth/oauth/callback/{provider}
```

— e.g. `https://api.myapp.com/auth/oauth/callback/google`, where `baseUrl` is
your `AppConfig.baseUrl` and `{provider}` is the factory's fixed `id`
(`'google'`, `'apple'`, ...). Paste the exact value into each console below —
a mismatch fails the exchange, since `redirect_uri` is exact-matched
server-side.

### Google

1. [Google Cloud Console](https://console.cloud.google.com/) → **APIs &
   Services → OAuth consent screen** — configure it first (External for a
   public app) if you haven't already.
2. **APIs & Services → Credentials → Create Credentials → OAuth client ID** →
   application type **Web application**.
3. Under **Authorized redirect URIs**, add `{baseUrl}/auth/oauth/callback/google`.
4. Copy the **Client ID** and **Client secret** into `GOOGLE_CLIENT_ID` /
   `GOOGLE_CLIENT_SECRET` in your `.env`.

```dart in:expression
OAuthProvider.google(
  clientId: const String.fromEnvironment('GOOGLE_CLIENT_ID'),
  clientSecret: const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
),
```

Default scopes: `openid`, `email`, `profile`. Default linking:
`OAuthLinking.byVerifiedEmail` — Google always asserts `email_verified`, so
this is safe to leave as-is.

### Apple

The longest setup of the eight, because Apple's `client_secret` isn't a
static string — it's an ES256 JWT zonai signs fresh for every token request,
from a private key only you hold.

1. **Register an App ID**, if you don't have one — [Apple Developer →
   Certificates, Identifiers & Profiles → Identifiers → App IDs**, with **Sign
   In with Apple** enabled as a capability.
2. **Register a Services ID** — same **Identifiers** page, type **Services
   IDs**. This is a *separate* identifier from your App ID, and its
   identifier string (e.g. `com.example.app.signin`) is the `clientId` you
   pass below — not your app's bundle ID.
3. On the Services ID, enable **Sign In with Apple**, then **Configure**:
   - **Primary App ID** — the App ID from step 1.
   - **Domains and Subdomains** — your app's domain, e.g. `myapp.com`.
   - **Return URLs** — `{baseUrl}/auth/oauth/callback/apple`.
4. **Create a Sign in with Apple key** — **Identifiers → Keys → Create a
   key**, enable **Sign In with Apple**, associate it with the App ID.
   Download the `.p8` file **immediately** — Apple lets you download it
   exactly once. Note the **Key ID** shown on the key's page.
5. Note your **Team ID** — top-right of the Apple Developer account page, or
   **Membership Details**.
6. Set four env vars:
   - `APPLE_CLIENT_ID` — the Services ID identifier from step 2.
   - `APPLE_TEAM_ID` — from step 5.
   - `APPLE_KEY_ID` — from step 4.
   - `APPLE_PRIVATE_KEY` — the `.p8` file's contents. `.env` is line-based, so
     a multi-line PEM can't go in as-is: replace every real newline with a
     literal `\n` before pasting it into `.env`, then undo that at read time
     in your schema, since `String.fromEnvironment` doesn't interpret escape
     sequences for you:

     ```
     # .env
     APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIGH...\n-----END PRIVATE KEY-----\n"
     ```

```dart in:expression
OAuthProvider.apple(
  clientId: const String.fromEnvironment('APPLE_CLIENT_ID'),
  teamId: const String.fromEnvironment('APPLE_TEAM_ID'),
  keyId: const String.fromEnvironment('APPLE_KEY_ID'),
  privateKey: const String.fromEnvironment(
    'APPLE_PRIVATE_KEY',
  ).replaceAll(r'\n', '\n'),
),
```

Two things unique to Apple worth knowing before you build a sign-in UI
around it:

- **The user's name arrives exactly once** — on the very first authorization,
  as a form-post `user` field, never again and never inside the `id_token`.
  Zonai's Apple factory leaves `OAuthClaimMap.name` unset for this reason; if
  you need the name, capture it from your `onExternalAuthFirstSeen` hook the
  first time a subject provisions, because there is no second chance to ask
  Apple for it.
- **The email may be a private relay address** (`abc123@privaterelay.appleid.com`)
  that forwards to the user's real inbox. Treat it as opaque — don't assume
  it round-trips to outbound mail you send from elsewhere.

Apple's `usesPkce` is `false` — Apple's own authorization endpoint doesn't
support PKCE the way the other seven do; the ES256 client-secret JWT is
Apple's substitute proof of possession.

### GitHub

1. [GitHub → Settings → Developer settings → OAuth Apps → New OAuth App](https://github.com/settings/developers).
2. **Homepage URL** — your app's URL.
3. **Authorization callback URL** — `{baseUrl}/auth/oauth/callback/github`.
4. Copy the **Client ID**, then **Generate a new client secret** and copy it.
   Set `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET`.

```dart in:expression
OAuthProvider.github(
  clientId: const String.fromEnvironment('GITHUB_CLIENT_ID'),
  clientSecret: const String.fromEnvironment('GITHUB_CLIENT_SECRET'),
),
```

GitHub isn't OIDC — there's no `id_token`, identity comes from `GET /user`.
Accounts with a private primary email return `email: null` there; zonai
falls back to `GET /user/emails` and uses the address marked both `primary`
and `verified`. Default scopes: `read:user`, `user:email`.

### Microsoft

1. [Azure Portal → Microsoft Entra ID → App registrations → New
   registration](https://portal.azure.com/).
2. **Redirect URI** — platform **Web**,
   `{baseUrl}/auth/oauth/callback/microsoft`.
3. **Certificates & secrets → New client secret** — copy the secret **value**
   (not the secret ID) immediately; it's hidden after you leave the page.
4. Copy the **Application (client) ID**. Set `MICROSOFT_CLIENT_ID` /
   `MICROSOFT_CLIENT_SECRET`.

```dart in:expression
OAuthProvider.microsoft(
  clientId: const String.fromEnvironment('MICROSOFT_CLIENT_ID'),
  clientSecret: const String.fromEnvironment('MICROSOFT_CLIENT_SECRET'),
),
```

Defaults to the `common` tenant (personal + work/school accounts), which is
why `OAuthEndpoints.issuer` is left unset — the templated multi-tenant
discovery document doesn't publish one concrete issuer. Pass `tenant:` with
your own directory's GUID to scope sign-in to a single organization and get a
concrete issuer for `id_token` verification.

### Facebook

1. [Meta for Developers → My Apps → Create App](https://developers.facebook.com/apps/) →
   add the **Facebook Login** product.
2. **Facebook Login → Settings → Valid OAuth Redirect URIs** —
   `{baseUrl}/auth/oauth/callback/facebook`.
3. **App settings → Basic** — copy **App ID** / **App Secret** into
   `FACEBOOK_CLIENT_ID` / `FACEBOOK_CLIENT_SECRET`.
4. The `email` permission needs [App Review](https://developers.facebook.com/docs/app-review)
   before it works for anyone outside your app's development roles.

```dart in:expression
OAuthProvider.facebook(
  clientId: const String.fromEnvironment('FACEBOOK_CLIENT_ID'),
  clientSecret: const String.fromEnvironment('FACEBOOK_CLIENT_SECRET'),
),
```

Not OIDC — no `id_token`, no JWKS; identity comes from the Graph API `/me`
call. Default scopes: `email`, `public_profile`.

### Discord

1. [Discord Developer Portal → New Application](https://discord.com/developers/applications).
2. **OAuth2 → Redirects** — add `{baseUrl}/auth/oauth/callback/discord`.
3. **OAuth2** tab — copy **Client ID** / **Client Secret** into
   `DISCORD_CLIENT_ID` / `DISCORD_CLIENT_SECRET`.

```dart in:expression
OAuthProvider.discord(
  clientId: const String.fromEnvironment('DISCORD_CLIENT_ID'),
  clientSecret: const String.fromEnvironment('DISCORD_CLIENT_SECRET'),
),
```

Not OIDC — identity comes from `GET /users/@me`. Default scopes: `identify`,
`email`.

### GitLab

1. [gitlab.com → User Settings → Applications → Add new
   application](https://gitlab.com/-/user_settings/applications).
2. **Redirect URI** — `{baseUrl}/auth/oauth/callback/gitlab`.
3. **Scopes** — check `openid`, `email`, `profile`.
4. Copy the **Application ID** / **Secret** into `GITLAB_CLIENT_ID` /
   `GITLAB_CLIENT_SECRET`.

```dart in:expression
OAuthProvider.gitlab(
  clientId: const String.fromEnvironment('GITLAB_CLIENT_ID'),
  clientSecret: const String.fromEnvironment('GITLAB_CLIENT_SECRET'),
),
```

This factory targets `gitlab.com`. For a self-managed instance, use
`OAuthProvider.custom(...)` with that instance's own endpoints instead — see
[Custom providers](#custom-providers).

### LinkedIn

1. [LinkedIn Developer Portal → Create app](https://www.linkedin.com/developers/apps).
2. Request the **"Sign In with LinkedIn using OpenID Connect"** product —
   auto-approved for most apps.
3. **Auth** tab → **Authorized redirect URLs for your app** —
   `{baseUrl}/auth/oauth/callback/linkedin`.
4. Copy the **Client ID** / **Client Secret** into `LINKEDIN_CLIENT_ID` /
   `LINKEDIN_CLIENT_SECRET`.

```dart in:expression
OAuthProvider.linkedin(
  clientId: const String.fromEnvironment('LINKEDIN_CLIENT_ID'),
  clientSecret: const String.fromEnvironment('LINKEDIN_CLIENT_SECRET'),
),
```

Default scopes: `openid`, `profile`, `email`.

## Custom providers

Anything without a named factory — an internal SSO provider, a self-managed
GitLab or Keycloak instance, any other OAuth2/OIDC issuer — via
`OAuthProvider.custom(...)`. Every field is explicit:

```dart in:expression
OAuthProvider.custom(
  id: 'acme',
  displayName: 'Acme SSO',
  endpoints: const OAuthEndpoints(
    authorization: 'https://sso.acme.example/authorize',
    token: 'https://sso.acme.example/token',
    userInfo: 'https://sso.acme.example/userinfo',
    issuer: 'https://sso.acme.example', // set alongside jwks to verify id_token
    jwks: 'https://sso.acme.example/.well-known/jwks.json',
  ),
  scopes: const ['openid', 'email', 'profile'],
  claims: const OAuthClaimMap(
    subject: 'sub',
    email: 'email',
    emailVerified: 'email_verified',
    name: 'name',
  ),
  clientId: const String.fromEnvironment('ACME_CLIENT_ID'),
  clientSecret: const String.fromEnvironment('ACME_CLIENT_SECRET'),
),
```

`id` is both the route segment and the identity key — pick something stable,
since it's part of `_oauth_identities`' unique index. `endpoints.issuer` and
`.jwks` are only needed together, and only if the provider issues a
verifiable `id_token`; leave both null for a provider whose identity comes
from `userInfo` alone (mirroring how GitHub, Discord and Facebook's built-in
factories work). `OAuthClaimMap`'s paths are dotted for nested fields — e.g.
`'picture.data.url'` for a userinfo response shaped
`{"picture": {"data": {"url": "..."}}}`.

## How sign-in works

**Redirect flow** (dashboard, web apps) — the client navigates the browser
through two round trips:

```
GET {baseUrl}/auth/oauth/start/{provider}?table=users&redirect_to=/dashboard
```

Zonai mints a single-use `state` (plus a PKCE `code_verifier` and OIDC
`nonce` where applicable), stores it server-side, and redirects to the
provider's consent screen. After the user approves, the provider redirects
back to the callback URL from the walkthroughs above with `code` and `state`:

```
GET {baseUrl}/auth/oauth/callback/{provider}?code=...&state=...
```

Zonai consumes the `state` (single-use — replaying it fails the same way an
unrecognized one does), exchanges `code` for tokens, verifies identity, mints
a session the same way password sign-in does, and redirects to `redirect_to`.
`redirect_to` must be a relative path or your app's own origin — anything
else is rejected before the redirect happens, so this can't be turned into an
open redirect.

**Native flow** (mobile / desktop apps using the provider's own SDK) — the
app runs `google_sign_in`, Sign in with Apple, etc. itself and hands zonai
the result directly: either the OIDC `idToken`, or the `code` +
`codeVerifier` + `redirectUri` the app generated and exchanged against.
Same identity resolution and session minting as the redirect flow, with no
server-side challenge row — the app already owns `state`/PKCE. This is the
primary path for Flutter apps built against `zonai_client`, not a fallback
behind the web flow.

Both flows end in the same place every other auth method does: the
`onExternalAuthFirstSeen` extension hook for provisioning, and the same JWT
issuance for session minting. If your schema already handles [external IdP
provisioning](/authentication/external-idp#provisioning-users), OAuth reuses
that hook as-is.

## Account linking

The first time a `(table, provider, subject)` triple is seen, zonai decides
whether it's a new user or an existing one via `OAuthLinking`, set per
provider:

| Value | Behavior |
| --- | --- |
| `byVerifiedEmail` (default) | Link to an existing row whose email matches — only when the provider asserts that email as verified. |
| `never` | Never link by email. An unrecognized subject always provisions a new row (or is rejected by your provisioning gate). |
| `always` | Link to an existing row whose email matches, **even when the provider does not assert it verified.** |

`always` is a footgun, not a convenience, and it's documented as one on the
enum itself: anyone who controls an email address — a typo'd signup, a
lapsed domain, a provider that never verifies email at all — can sign in as
the zonai account that owns it, without ever proving they control the inbox.
Reach for it only against a provider you know guarantees verified emails out
of band (an internal SSO where your own IT already verifies addresses, say).
For every public-facing provider in the built-in list, the default
`byVerifiedEmail` is the right choice and every factory already defaults to
it.

## Signing into the dashboard with OAuth

Combine `OAuth` with [`AsAdmin`](/authentication/admin-accounts) on a table
to let admins sign into the zonai dashboard through a provider instead of a
dashboard-only password:

```dart no-analyze
final class AdminTable extends AuthTable<Admin>
    with OAuth, AsAdmin {
  @override
  List<OAuthProvider> get oauthProviders => [
    OAuthProvider.google(
      clientId: const String.fromEnvironment('GOOGLE_CLIENT_ID'),
      clientSecret: const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
    ),
  ];
}
```

The admin-specific entry point (`startAdminOAuth`) resolves the `AsAdmin`
table configured for OAuth the same way admin sign-in already resolves it for
password auth — no separate admin OAuth pipeline. One deliberate difference
from the regular flow: **admin sign-in never auto-provisions.** A subject
that doesn't already match an admin row is rejected rather than silently
creating one — admin accounts are still created explicitly, via `zonai db
admin add` or your own provisioning code, never as a side effect of someone
signing in with the right Google account.

## OAuth vs. External Identity Providers

Both let a user sign in without a zonai password. The difference is who runs
the OAuth handshake:

| | OAuth (this page) | [External IdP](/authentication/external-idp) |
| --- | --- | --- |
| Who talks to the provider | zonai — authorization redirect, code exchange, token verification | Your existing IdP (Supabase Auth, Auth0, Clerk, ...); zonai only verifies the JWT it hands you |
| Setup | Register an app in each provider's console; declare `oauthProviders` | Point `AppConfig.externalIdps` at your IdP's issuer + JWKS or shared secret |
| Best for | Greenfield apps where zonai owns auth end-to-end and you want "Sign in with Google" directly | Apps that already have an IdP for something zonai can't replicate (phone+SMS OTP, enterprise SSO, an existing user base) |
| Session | A zonai JWT, revocable via the `_jwt` table like any other session | A zonai JWT is still minted on first-seen provisioning, but the *inbound* IdP token itself can't be revoked by zonai — it's not zonai's token |

If you're unsure: this page is the greenfield choice — a new app that wants
provider sign-in without operating a separate identity service. Reach for
[External Identity Providers](/authentication/external-idp) when that
separate identity service already exists and you'd rather not duplicate it.

## See also

- **[External Identity Providers](/authentication/external-idp)** — trusting
  an existing IdP's JWT instead of running OAuth yourself.
- **[Auth Tables](/schemas/auth-tables)** — `AuthTable`, the other auth
  mixins, and column setup.
- **[Admin Accounts](/authentication/admin-accounts)** — `AsAdmin`, elevated
  JWT claims, the CLI for creating admins.
- **[Environment Variables](/configuration/environment-variables)** — how
  `.env` and `String.fromEnvironment` fit together for provider credentials.
- **[Authentication Overview](/authentication/overview)** — the JWT model
  every auth method, including OAuth, shares.
