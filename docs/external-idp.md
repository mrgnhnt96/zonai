# External identity providers (BYO auth)

Zonai accepts JWTs minted by external identity providers (Supabase Auth, Auth0, custom OIDC, etc.) and maps their users into zonai auth collections. This lets a project keep an existing identity stack and use zonai purely as a data / rules / extensions / real-time layer.

External-IdP trust is **opt-in per issuer**. With `AppConfig.externalIdps` empty (the default), zonai trusts only the tokens it mints itself — nothing changes for existing deployments.

## When to use this

- The project already has an IdP that zonai's built-in auth can't replicate (phone+SMS OTP, social logins, enterprise SSO, custom OIDC).
- You want zonai's [rules](rules.md), [extensions](extensions.md), real-time streams, and Dart-native schemas without giving up the existing identity stack.
- You're running multiple services that already share an IdP and want zonai to slot in alongside them.

For greenfield apps where zonai can own auth end-to-end, the built-in [password / OTP / magic-link flows](auth.md) are simpler — don't reach for external IdPs unless you need them.

## How it works

1. Client sends a request with `Authorization: Bearer <token>`.
2. Zonai's JWT extraction tries the **internal** verifier first (HS256 against `AppConfig.jwtSecret`).
3. If internal verification fails, zonai inspects the token's `iss` claim and matches it against the configured `AppConfig.externalIdps`.
4. If an entry matches, the matched variant's verifier validates the signature, algorithm, `iss`, `aud`, `exp`, and `nbf` claims.
5. On success, zonai looks up the user row in the IdP's mapped `authTable` by `id == sub`.
6. The resolved row becomes `Jwt.user`; the rest of the request proceeds normally — rules, operations, extensions all run as if the user had signed in through zonai's own flow.

**External tokens skip the `_jwt` revocation table check.** Zonai didn't mint them and has no `jti` to look up. Revocation is the IdP's responsibility; keep external token TTLs short.

## Configuration

Each entry in `AppConfig.externalIdps` is a sealed [`ExternalIdpConfig`](https://github.com/mrgnhnt96/zonai/blob/main/libs/zonai_schema/lib/src/config/external_idp_config.dart) variant. Two variants ship:

| Variant | When to use |
| --- | --- |
| [`SharedSecretIdpConfig`](#shared-secret-hs256) | IdPs that sign tokens with a symmetric HMAC secret (Supabase Auth, many custom internal IdPs). |
| `JwksIdpConfig` | IdPs that publish their public keys via a JWKS endpoint (Auth0, Clerk, Cognito, Firebase Auth, any OIDC provider). **Verification path is not yet implemented** — the config type exists but throws `UnimplementedError` at runtime. Track [#2](https://github.com/mrgnhnt96/zonai/issues/2). |

Multiple IdPs can be configured simultaneously — a deployment can trust Supabase Auth for end users and a different IdP for admins.

## Shared secret (HS256)

Use this for any IdP that signs JWTs with HS256 and a shared symmetric secret.

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: '...',
    jwtSecret: '...',
    externalIdps: const [
      SharedSecretIdpConfig(
        issuer: 'https://your-project.supabase.co/auth/v1',
        audience: 'authenticated',
        authTable: 'users',
        secret: const String.fromEnvironment('SUPABASE_JWT_SECRET'),
      ),
    ],
  );
}
```

**Field reference:**

| Field | Required | Purpose |
| --- | --- | --- |
| `issuer` | yes | The `iss` claim incoming tokens must declare exactly. |
| `audience` | yes | The `aud` claim incoming tokens must declare exactly. Accepted as a String or a List that contains this value. |
| `authTable` | yes | The zonai auth collection that users from this IdP map into. The `sub` claim is looked up against this table's `id` column. |
| `secret` | yes | The HMAC secret used to verify signatures. Treat as a production secret; bake in via `const String.fromEnvironment('NAME')` rather than hardcoding. The `const` is required — without it, `fromEnvironment` returns the runtime default (`''`) instead of the compile-time-injected value. |
| `adminClaimPath` | no | See [Admin-claim mapping](#admin-claim-mapping). |
| `adminClaimEquals` | no | See [Admin-claim mapping](#admin-claim-mapping). |

**Algorithm pinning:** the verifier rejects any `alg` header other than `HS256`. Tokens with `alg=none` or `alg=RS256` (the classic confused-deputy attack) fail before the signature check runs.

## Per-IdP walkthroughs

### Supabase Auth

Supabase signs project JWTs with HS256 using the project's JWT secret. Get it from the dashboard (Settings → API → JWT Settings).

```dart
SharedSecretIdpConfig(
  issuer: 'https://YOUR_PROJECT_REF.supabase.co/auth/v1',
  audience: 'authenticated',
  authTable: 'users',  // your zonai auth collection
  secret: const String.fromEnvironment('SUPABASE_JWT_SECRET'),
  // Optional — flag maintainers from Supabase's app_metadata:
  adminClaimPath: 'app_metadata.is_admin',
  adminClaimEquals: true,
),
```

Notes:

- Supabase's `aud` for end-user tokens is `'authenticated'`; anonymous-session tokens use `'authenticated'` as well (with `'is_anonymous': true` in the claims).
- The `sub` claim is Supabase's `auth.users.id` UUID. Your zonai `users` collection should use this as the primary key so the lookup matches.
- For phone-based OTP via Twilio, leave that flow on Supabase Auth and let it issue the JWTs.

### Auth0

`JwksIdpConfig` (forthcoming). Once shipped:

```dart
JwksIdpConfig(
  issuer: 'https://YOUR_TENANT.auth0.com/',
  audience: 'https://your-api.example/',
  authTable: 'users',
  jwksUrl: 'https://YOUR_TENANT.auth0.com/.well-known/jwks.json',
  adminClaimPath: 'https://your-api.example/role',
  adminClaimEquals: 'admin',
),
```

### Custom OIDC / internal HMAC IdP

Anything that signs JWTs with HS256 and a shared secret you control:

```dart
SharedSecretIdpConfig(
  issuer: 'https://internal-auth.your-company.example',
  audience: 'zonai-data-api',
  authTable: 'employees',
  secret: const String.fromEnvironment('INTERNAL_IDP_JWT_SECRET'),
),
```

## Admin-claim mapping

External tokens can be flagged as admin based on a configurable claim value. When `adminClaimPath` is unset (default), external tokens never derive admin status — use row-level rules on `authTable` for that decision instead.

```dart
SharedSecretIdpConfig(
  // ... required fields ...
  adminClaimPath: 'app_metadata.is_admin',  // dotted path into claims
  adminClaimEquals: true,                    // == comparison
),
```

The path walks nested maps:

- `'role'` reads `claims['role']` — Auth0-common shape with the role at the top level.
- `'app_metadata.is_admin'` reads `claims['app_metadata']['is_admin']` — Supabase-common shape.
- Any nested boolean, string, or number is comparable.

**Limitations:** the check is equality-only. List-membership claims (e.g. Cognito's `cognito:groups` as a `List<String>`) can't be expressed here — use a row-level rule that derives admin from the user row's own columns instead.

When the claim resolves and equals the configured value, `Jwt.admin = (isAdmin: true, canEdit: true)`. Otherwise `(isAdmin: false, canEdit: null)`.

## Provisioning users

The current implementation requires the user row to already exist in `authTable` before an external token is accepted. If the row is missing, the request fails with `UserNotFoundAuthException`.

For deployments where users are created out-of-band (admin script, separate provisioning service, or a webhook from the IdP), this is sufficient.

For deployments that want zonai to auto-create the user row on first sign-in (the typical pattern), an `onExternalAuthFirstSeen` extension hook is tracked at [#2](https://github.com/mrgnhnt96/zonai/issues/2). Until that ships, options:

- Provision via an IdP webhook (Supabase Auth, Auth0, etc. all support outbound webhooks on user creation).
- Provision on first sign-in from the client (extra round trip, brittle on network failures — not recommended).
- Periodic reconcile job (eventually-consistent — acceptable for low-churn user bases).

## Security considerations

External-IdP trust expands zonai's attack surface in ways the schema-layer types already enforce or document.

**At the type level (compile-time / config-load-time):**

- `iss`, `aud`, and `authTable` are required on every variant. There's no way to construct a config that skips audience binding (which would enable token confusion across services).
- Variants pin their algorithm: `SharedSecretIdpConfig` is HS256-only, `JwksIdpConfig` will be RS256/ES256-only. Reject `alg=none` and confused-deputy at the variant level rather than relying on header parsing in the verifier.
- Unknown variant `type` values throw `ArgumentError` at config load — misconfiguration fails loudly at startup, not at request time.

**At verification time:**

- Standard `iss`, `aud`, `exp`, `nbf` checks per RFC 7519.
- `exp` is **required** (the RFC technically permits its absence; zonai treats missing `exp` as a misconfigured token).
- Constant-time signature comparison.

**Operational responsibilities:**

- Treat HMAC secrets and JWKS URLs as production secrets. Bake them in via env-injected `const String.fromEnvironment('NAME')` rather than hardcoding. The `const` is load-bearing — without it the call evaluates at runtime and returns the default empty string instead of the compile-time-injected value.
- Keep external token TTLs short — zonai cannot revoke a token it didn't issue. Compromised tokens stay valid until natural expiry.
- For multi-IdP setups, the auth check loops through every configured `iss`. Order configs so the most-frequently-hit IdP comes first.

## Limitations

- `JwksIdpConfig` runtime not yet implemented (asymmetric verification, JWKS fetch + cache, key rotation). Tracked in [#2](https://github.com/mrgnhnt96/zonai/issues/2).
- `onExternalAuthFirstSeen` provisioning hook not yet implemented. Tracked in [#2](https://github.com/mrgnhnt96/zonai/issues/2).
- Admin-claim mapping is equality-only. List-membership not yet supported.
- External tokens are not recorded in the `_jwt` table; explicit token-level revocation through zonai is not possible.

## See also

- **[auth.md](auth.md)** — zonai's built-in auth flows (password, OTP, magic link).
- **[rules.md](rules.md)** — row-level authorization for external-authenticated users.
- **[extensions.md](extensions.md)** — lifecycle hooks (the future `onExternalAuthFirstSeen` will live here).
- **[#2](https://github.com/mrgnhnt96/zonai/issues/2)** — design RFC for the external-IdP feature, including the open follow-ups.
