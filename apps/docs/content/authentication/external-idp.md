---
title: External Identity Providers
description: Trust JWTs minted by Supabase Auth, Auth0, Clerk or any OIDC provider, and map their users into a Zonai auth collection.
---

Zonai can accept JWTs it did not mint. Point `AppConfig.externalIdps` at an issuer and tokens from that IdP are verified on arrival and mapped onto a row in one of your auth collections — so a project keeps its existing identity stack and uses Zonai for data, rules, extensions and live streams.

**Trust is opt-in per issuer.** `externalIdps` is empty by default, and while it is empty Zonai trusts only its own tokens. There is no "accept any valid JWT" mode, and no way to reach one by accident.

## When this is the right tool

Reach for it when an identity stack already exists and duplicating it would be the mistake:

- an IdP does something Zonai's built-in auth does not — phone/SMS OTP, enterprise SSO, an unusual social provider;
- several services already share an IdP and Zonai is joining them;
- there is an existing user base you are not going to migrate.

For a greenfield app, [password / OTP / magic link](/authentication/overview) is simpler, and [OAuth](/authentication/oauth) covers "Sign in with Google" without a second identity service. The distinction that matters: **OAuth is Zonai running the handshake; this is Zonai trusting the result of someone else's.** [OAuth vs. External Identity Providers](/authentication/oauth#oauth-vs-external-identity-providers) compares them directly.

## How a request is verified

There is no sign-in call and no token exchange. The client sends the **IdP's own token** on every request, exactly where a Zonai token would go, and the pipeline resolves it:

1. The payload is base64-decoded **without verifying anything** to read its `iss`. That value selects a configured IdP and nothing else — no decision rests on it.
2. If no `iss` matches, the token is not an external one and normal handling continues. An unknown issuer is not an error.
3. The matched config's secret or JWKS keys verify the signature, algorithm, `aud`, `exp` and `nbf`. A token that matches an issuer but fails any of these is rejected outright — it never falls through to being treated as a Zonai token.
4. The verified `sub` is looked up against the `id` column of the configured `authTable`. A missing row goes to [provisioning](#provisioning-users); a still-missing row fails with `UserNotFoundAuthException`.
5. A `Jwt` is assembled in memory from the claims and the row, and the request proceeds through [rules](/rules/overview) like any other.

Two consequences worth holding on to:

- **Nothing is minted.** That `Jwt` exists for the life of the request. The client keeps presenting the IdP's token, which is why there is no refresh endpoint on this path.
- **Revocation is the IdP's job.** External tokens skip the `_jwt` revocation table on purpose — Zonai cannot revoke a token it did not issue, so a compromised one stays valid until it expires. Keep external TTLs short; that is the only lever there is.

The `Jwt`'s expiry is the token's `exp`, and its id is the token's `jti` when it has one, or `ext:<issuer>:<sub>` when it does not.

## Configuring an issuer

Each entry is one of two variants, chosen by how the IdP signs:

| Variant | Use it when | Verifies with |
|---|---|---|
| `SharedSecretIdpConfig` | The IdP signs with a symmetric HMAC secret — HS256. | A secret you hold. |
| `JwksIdpConfig` | The IdP publishes public keys at a JWKS endpoint — RS256/384/512, ES256/384/512. | Keys fetched at runtime. **No secret in your config.** |

Prefer JWKS when the IdP offers it: there is no shared secret to leak, and key rotation happens without a redeploy. Covers Auth0, Clerk, Cognito, Firebase Auth, Okta and any OIDC-compliant provider.

```dart in:app-config
externalIdps: const [
  JwksIdpConfig(
    issuer: 'https://YOUR_TENANT.auth0.com/',
    audience: 'https://your-api.example/',
    authTable: 'users',
    jwksUrl: 'https://YOUR_TENANT.auth0.com/.well-known/jwks.json',
  ),
],
```

The HMAC form, for an IdP that offers nothing else:

```dart in:expression
SharedSecretIdpConfig(
  issuer: 'https://internal-auth.your-company.example',
  audience: 'zonai-data-api',
  authTable: 'employees',
  secret: const String.fromEnvironment('INTERNAL_IDP_JWT_SECRET'),
),
```

**The `const` on `String.fromEnvironment` is load-bearing.** Without it the call runs at runtime and returns the default empty string instead of the value baked in at compile time, and the symptom is every token failing verification with a config that looks correct. See [Environment & Secrets](/deployment/environment-and-secrets).

### Fields

| Field | Variant | |
|---|---|---|
| `issuer` | both | The `iss` incoming tokens must declare **exactly**. Trailing slashes and subdomains count. |
| `audience` | both | The `aud` incoming tokens must declare exactly. A list containing the value is accepted. |
| `authTable` | both | The auth collection these users map into. `sub` is looked up against its `id` column. |
| `secret` | shared secret | The HMAC secret. Inject it; never commit it. |
| `jwksUrl` | JWKS | The IdP's JWKS endpoint, usually discoverable from `${issuer}/.well-known/openid-configuration`. |
| `cacheTtl` | JWKS | How long a fetched key set is reused. Default 1 hour. |
| `fetchTimeout` | JWKS | How long a cold-cache fetch may take. Default 2 seconds. |
| `adminClaimPath`, `adminClaimEquals` | both | See [Admin claims](#admin-claims). |

Multiple IdPs can be configured at once — end users from one, staff from another — and each is matched by its own `iss`. Order the list with the busiest issuer first; matching is a linear scan.

The JWKS key set is cached by URL for the life of the process, so a verifier outlives a single request. Without that, every token would trigger a fresh fetch.

## Required claims

| Claim | | |
|---|---|---|
| `iss` | required | Must match a configured `issuer` exactly. |
| `aud` | required | Must match that IdP's `audience`. String or list. |
| `sub` | required | The row id in `authTable`. Empty or non-string is rejected. |
| `exp` | required | **Zonai rejects a token with no `exp`**, though the JWT spec permits its absence. |
| `nbf` | optional | Honoured when present. |

The algorithm must match the variant: `HS256` for a shared secret, one of the RS/ES family for JWKS. Anything else — `alg=none` included — is refused before the signature check runs.

## Admin claims

An external token can carry admin status, but only if you say which claim means it. `adminClaimPath` is a dotted path into the verified claims and `adminClaimEquals` is compared to the value at that path with `==`:

```dart no-analyze
adminClaimPath: 'app_metadata.is_admin',  // dotted path into claims
adminClaimEquals: true,                    // compared with ==
```

- `'role'` reads `claims['role']` — the common Auth0 shape.
- `'app_metadata.is_admin'` reads `claims['app_metadata']['is_admin']` — the common Supabase shape.
- Booleans, strings and numbers all compare.

When it matches, the request's `Jwt` carries `(isAdmin: true, canEdit: true)`. When `adminClaimPath` is unset — the default — an external token **never** derives admin status from its claims, and the decision belongs to a [row rule](/rules/row-rules) reading the user's own row instead.

**Only where the IdP controls the claim.** Put the flag somewhere the user cannot write. On Supabase that means `app_metadata`, never `user_metadata`; on any IdP it means a namespace the end user has no API for.

**Equality only.** A list-membership claim — Cognito's `cognito:groups`, for instance — cannot be expressed here. Derive admin from the row in a rule instead.

## Provisioning users

A verified token whose `sub` has no row is the interesting case, because the signature is valid and the user is real; there is simply nothing to attach them to. Zonai calls the auth collection's `onExternalAuthFirstSeen` hook, and the row it creates is used immediately:

```dart in:extension-user
@override
Future<void> onExternalAuthFirstSeen(Map<String, Object?> claims) async {
  mutate.create.one(
    tableName: tableName,
    object: <String, dynamic>{
      'id': claims['sub'] as String,
      'email': claims['email'] as String?,
      // … map the rest of the claims onto this collection's columns
    },
  );
}
```

`id` must be the `sub`, or the next request from the same user provisions all over again.

**Mutations here flush inline**, not after the request transaction, so the auth pipeline can re-fetch the row and carry on within the same request.

**The hook runs under a `ProvisioningJwt` scoped to that one auth table.** It can insert the row your normal row rules would refuse from an end user, and it cannot touch any other collection — a mutation aimed elsewhere is rejected with an error saying so. A buggy provisioning hook is contained by construction rather than by review.

**Not implementing it is a valid choice.** The default is a no-op, and an unknown `sub` then fails with `UserNotFoundAuthException` until the row exists — which is what you want if users are created out of band by an admin tool, an IdP webhook or a reconcile job. A hook that inspects `claims` and returns without queueing anything is how you refuse a specific user; the same exception results.

### First-seen provisioning is rate limited

Provisioning is the one path where an inbound token creates a row, so it is throttled per auth table, per client IP — **30 attempts per hour** by default. The vector it bounds is a compromised or over-permissive IdP minting unique `sub` claims to fill a table.

```dart in:project-file
final class UsersRateLimits extends AuthTableRateLimits<UserTable, User> {
  UsersRateLimits() : super(users);

  @override
  Future<RateLimitPolicy?> externalIdpProvisioningPolicy() async {
    return const RateLimitPolicy(maxRequests: 10, window: Duration(hours: 1));
  }
}
```

Returning `null` disables it. Once a `sub` is provisioned, that user's requests never touch this limit again — it applies to first sight only. See [Configuring Policies](/rate-limiting/configuring-policies).

## What this does not give you

- **Token revocation.** External tokens are not recorded in `_jwt`. Short TTLs at the IdP are the mitigation.
- **List-membership admin claims.** Equality only; use a row rule.
- **A Zonai session.** No refresh, no logout — the IdP owns the session's lifetime, and [Session Management](/authentication/session-management) describes the other path.

## Related

- **[Supabase Auth](/authentication/external-idp-supabase)** — the walkthrough, including which of the two variants your project needs.
- **[OAuth](/authentication/oauth)** — when you want Zonai to run the handshake itself.
- **[Row Rules](/rules/row-rules)** — where authorization for externally-authenticated users belongs.
- **[JWT Claims](/rules/jwt-claims)** — what rules can read off a resolved token.
