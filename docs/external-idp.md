# External identity providers (BYO auth)

Zonai accepts JWTs minted by external identity providers (Supabase Auth, Auth0, custom OIDC, etc.) and maps their users into zonai auth collections. This lets a project keep an existing identity stack and use zonai purely as a data / rules / extensions / real-time layer.

External-IdP trust is **opt-in per issuer**. With `AppConfig.externalIdps` empty (the default), zonai trusts only the tokens it mints itself — nothing changes for existing deployments.

## When to use this

- The project already has an IdP that zonai's built-in auth can't replicate (phone+SMS OTP, social logins, enterprise SSO, custom OIDC).
- You want zonai's [rules](rules.md), [extensions](extensions.md), real-time streams, and Dart-native schemas without giving up the existing identity stack.
- You're running multiple services that already share an IdP and want zonai to slot in alongside them.

For greenfield apps where zonai can own auth end-to-end, the built-in [password / OTP / magic-link flows](auth.md) are simpler — don't reach for external IdPs unless you need them.

## Configuration

Each entry in `AppConfig.externalIdps` is a sealed [`ExternalIdpConfig`](https://github.com/mrgnhnt96/zonai/blob/main/libs/zonai_schema/lib/src/config/external_idp_config.dart) variant:

| Variant                                         | When to use                                                                                                        |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| [`SharedSecretIdpConfig`](#shared-secret-hs256) | IdPs that sign tokens with a symmetric HMAC secret (Supabase Auth, many custom internal IdPs).                     |
| [`JwksIdpConfig`](#jwks-rs256--es256)           | IdPs that publish their public keys via a JWKS endpoint (Auth0, Clerk, Cognito, Firebase Auth, any OIDC provider). |

Multiple IdPs can be configured simultaneously — a deployment can trust Supabase Auth for end users and a different IdP for admins.

## Required JWT claims

Every external token must include these standard claims. Missing or mismatched values are the most common source of auth failures.

| Claim | Required | Notes                                                                                                                                                                                |
| ----- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `iss` | yes      | Must match the `issuer` field of a configured IdP **exactly** — trailing slashes and subdomains matter.                                                                              |
| `aud` | yes      | Must match the `audience` field exactly. Accepted as a string or a list that contains the configured value.                                                                          |
| `sub` | yes      | Used to look up the user row in `authTable` by `id`. A token whose `sub` has no matching row fails with `UserNotFoundAuthException` unless `onExternalAuthFirstSeen` provisions one. |
| `exp` | yes      | Expiry timestamp. Zonai treats tokens without `exp` as invalid, even though the JWT spec permits its absence.                                                                        |
| `nbf` | no       | Not-before timestamp. Honored if present — tokens are rejected before their `nbf` time.                                                                                              |

The signing algorithm must also match the configured variant: `HS256` for `SharedSecretIdpConfig`, or `RS256` / `RS384` / `RS512` / `ES256` / `ES384` / `ES512` for `JwksIdpConfig`. Any other algorithm (including `alg=none`) is rejected before the signature check runs.

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

| Field              | Required | Purpose                                                                                                                                                                                                                                                                                    |
| ------------------ | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `issuer`           | yes      | The `iss` claim incoming tokens must declare exactly.                                                                                                                                                                                                                                      |
| `audience`         | yes      | The `aud` claim incoming tokens must declare exactly. Accepted as a String or a List that contains this value.                                                                                                                                                                             |
| `authTable`        | yes      | The zonai auth collection that users from this IdP map into. The `sub` claim is looked up against this table's `id` column.                                                                                                                                                                |
| `secret`           | yes      | The HMAC secret used to verify signatures. Treat as a production secret; bake in via `const String.fromEnvironment('NAME')` rather than hardcoding. The `const` is required — without it, `fromEnvironment` returns the runtime default (`''`) instead of the compile-time-injected value. |
| `adminClaimPath`   | no       | See [Admin-claim mapping](#admin-claim-mapping).                                                                                                                                                                                                                                           |
| `adminClaimEquals` | no       | See [Admin-claim mapping](#admin-claim-mapping).                                                                                                                                                                                                                                           |

## JWKS (RS256 / ES256)

Use this for any IdP that publishes its signing public keys at a JWKS endpoint (RFC 7517). Covers the bulk of managed IdPs — Auth0, Clerk, AWS Cognito, Firebase Auth, Okta, any OIDC-compliant provider.

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: '...',
    jwtSecret: '...',
    externalIdps: const [
      JwksIdpConfig(
        issuer: 'https://YOUR_TENANT.auth0.com/',
        audience: 'https://your-api.example/',
        authTable: 'users',
        jwksUrl: 'https://YOUR_TENANT.auth0.com/.well-known/jwks.json',
      ),
    ],
  );
}
```

**Field reference:**

| Field              | Required | Purpose                                                                                                                     |
| ------------------ | -------- | --------------------------------------------------------------------------------------------------------------------------- |
| `issuer`           | yes      | The `iss` claim incoming tokens must declare exactly.                                                                       |
| `audience`         | yes      | The `aud` claim incoming tokens must declare exactly. Accepted as a String or a List that contains this value.              |
| `authTable`        | yes      | The zonai auth collection that users from this IdP map into. The `sub` claim is looked up against this table's `id` column. |
| `jwksUrl`          | yes      | URL of the IdP's JWKS endpoint. Typically discoverable via `${issuer}/.well-known/openid-configuration`'s `jwks_uri` field. |
| `cacheTtl`         | no       | How long the parsed JWKS is reused before the next refresh. Defaults to 1h.                                                 |
| `fetchTimeout`     | no       | Maximum time to wait for a JWKS fetch on a cold cache. Defaults to 2s.                                                      |
| `adminClaimPath`   | no       | See [Admin-claim mapping](#admin-claim-mapping).                                                                            |
| `adminClaimEquals` | no       | See [Admin-claim mapping](#admin-claim-mapping).                                                                            |

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

When an external IdP token's `sub` doesn't match any existing row in `authTable`, zonai invokes the auth collection's `onExternalAuthFirstSeen` extension hook (default: no-op). The hook receives the verified claims and may insert the missing row so the auth flow can resolve `Jwt.user` and proceed.

```dart
import 'package:zonai_schema/zonai_schema.dart';
import 'package:my_app/src/schemas/users.dart';

final class UsersExtension extends Extension<User> with AuthExtension<User> {
  UsersExtension() : super(users);

  @override
  Future<void> onExternalAuthFirstSeen(Map<String, Object?> claims) async {
    // Convert the verified claims into a row shape for this collection,
    // then queue the insert. Mutations queued during this hook are
    // flushed inline (not after the request transaction) so the auth
    // pipeline can re-fetch the new row immediately.
    mutate.create.one(
      tableName: users.table.name,
      object: <String, dynamic>{
        'id': claims['sub'] as String,
        'email': claims['email'] as String?,
        // … map other claims into your schema's columns
      },
    );
  }
}
```

**Restricted scope.** During `onExternalAuthFirstSeen` the hook runs under a `ProvisioningJwt` scoped to the configured `authTable`. Mutations targeting any other collection are rejected with a clear error — a buggy hook cannot mutate unrelated data.

**Refusing to provision.** Return from the hook without queueing a mutation (the default behavior, or a hook that decides `claims` doesn't satisfy required invariants) and the auth request fails with `UserNotFoundAuthException`.

**Alternative provisioning paths.** If you'd rather create users out-of-band (admin script, IdP webhook, periodic reconcile), leave `onExternalAuthFirstSeen` unimplemented. The auth flow will reject unknown `sub`s with `UserNotFoundAuthException` until the row exists.

**Rate limiting.** HTTP deployments rate-limit first-seen provisioning per **(auth-table, IP)** — defaulting to 30 attempts per hour. Tune this per auth table by overriding `AuthTableRateLimits.externalIdpProvisioningPolicy`:

```dart
final class UsersRateLimits extends AuthTableRateLimits<UserTable, User> {
  UsersRateLimits() : super(users);

  @override
  Future<RateLimitPolicy?> externalIdpProvisioningPolicy() async {
    return const RateLimitPolicy(maxRequests: 10, window: Duration(hours: 1));
  }
}
```

Once a `sub` is provisioned, subsequent requests for that user bypass the rate limit entirely.

## Security considerations

- Treat HMAC secrets and JWKS URLs as production secrets. Bake them in via `const String.fromEnvironment('NAME')` rather than hardcoding. The `const` is load-bearing — without it the call evaluates at runtime and returns the default empty string instead of the compile-time-injected value.
- **Keep external token TTLs short.** Zonai cannot revoke a token it didn't issue — external tokens skip the `_jwt` revocation table. Compromised tokens stay valid until natural expiry.
- For multi-IdP setups, order configs so the most-frequently-hit IdP comes first.

## Limitations

- Admin-claim mapping is equality-only. List-membership claims (e.g. Cognito's `cognito:groups` as a `List<String>`) can't be expressed in `adminClaimPath` / `adminClaimEquals` — use a row-level rule that derives admin from the user row's own columns instead.
- External tokens are not recorded in the `_jwt` table; explicit token-level revocation through zonai is not possible.

## See also

- **[auth.md](auth.md)** — zonai's built-in auth flows (password, OTP, magic link).
- **[rules.md](rules.md)** — row-level authorization for external-authenticated users.
- **[extensions.md](extensions.md)** — lifecycle hooks including `onExternalAuthFirstSeen`.
