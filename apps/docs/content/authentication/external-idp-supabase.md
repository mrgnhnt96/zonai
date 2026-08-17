---
title: Supabase Auth as an IdP
description: Keep Supabase Auth for sign-in and use Zonai for data — which of the two key models your project has, and how to tell.
---

Supabase Auth is the most common reason to reach for [external identity providers](/authentication/external-idp): a project already has phone/SMS OTP, social logins and anonymous sessions working there, and wants Zonai for the data layer rather than a second identity stack.

Zonai ships a `SupabaseExternalIdp` helper so you configure a **project ref** rather than transcribing three URLs.

## First, find out which key model your project has

Supabase moved to asymmetric JWTs (ECC P-256, RS256, ES256) in late 2025. Projects created after that default to it; older projects keep a legacy HS256 shared secret until they rotate. **The two need different config, and picking wrong fails every token.**

The fastest check does not involve the dashboard at all:

```
https://<projectRef>.supabase.co/auth/v1/.well-known/jwks.json
```

A `{"keys":[...]}` body means asymmetric is active — use `SupabaseExternalIdp.jwks`. A 404, or a body with no `keys`, means legacy-only — use `SupabaseExternalIdp.sharedSecret`.

In the dashboard the same answer lives under **Project Settings → API → JWT Keys**:

| What the page shows | Use |
|---|---|
| A Current Key of `ECC (P-256)`, `RS256`, `ES256` or similar | `SupabaseExternalIdp.jwks` |
| Only "Legacy HS256 (Shared Secret)", no asymmetric Current Key | `SupabaseExternalIdp.sharedSecret` |
| Both, mid-rotation | `SupabaseExternalIdp.jwks` |

Mid-rotation resolves to JWKS because new tokens are already signed with the asymmetric key; the legacy entry only verifies tokens minted before the rotation, and those age out on their own TTL.

## Asymmetric (JWKS)

```dart in:app-config
externalIdps: [
  SupabaseExternalIdp.jwks(
    projectRef: 'abcdefghijklmnopqrst',
    authTable: 'profiles',
    adminClaimPath: 'app_metadata.is_admin',
    adminClaimEquals: true,
  ),
],
```

No secret appears anywhere in that config, which is the reason to prefer it. The helper derives the rest:

- `issuer` → `https://<projectRef>.supabase.co/auth/v1`
- `jwksUrl` → `<issuer>/.well-known/jwks.json`
- `audience` → `authenticated`, which is Supabase's `aud` for both verified and anonymous sessions

`cacheTtl` (1 hour) and `fetchTimeout` (2 seconds) carry the same defaults as any [`JwksIdpConfig`](/authentication/external-idp#configuring-an-issuer), and `audience` is only worth overriding if a JWT hook mints a non-standard `aud`.

**`projectRef` is the ref, not the URL** — `abcdefghijklmnopqrst`, not `https://abcdefghijklmnopqrst.supabase.co`. The helper validates it as lowercase alphanumeric and throws at startup rather than at the first auth request, because pasting the whole URL is the mistake everyone makes once.

## Legacy HS256 (shared secret)

```dart in:app-config
externalIdps: [
  SupabaseExternalIdp.sharedSecret(
    projectRef: 'abcdefghijklmnopqrst',
    authTable: 'profiles',
    secret: const String.fromEnvironment('SUPABASE_JWT_SECRET'),
  ),
],
```

The secret is under **Project Settings → API → JWT Keys → Legacy HS256 (Shared Secret) → Reveal**. Put it in `.env` beside `zonai.yaml` (or the flavor equivalent — `.env.dev`, `.env.prod`):

```sh
SUPABASE_JWT_SECRET=<hmac-secret>
```

`zonai compile` passes each entry to `dart compile exe` as a `-D` define, baking it into the worker binary. [Config Flavors](/core-concepts/config-flavors) covers the lookup rules and per-flavor overrides.

**The `const` is load-bearing.** The helper takes a plain `String`, so a non-`const` `String.fromEnvironment` compiles — and then returns the runtime default of `''` instead of the injected value, so every token fails verification against a config that reads as correct.

## The claims you get

A verified Supabase session carries, alongside the standard `iss`/`aud`/`exp`/`iat`:

```json
{
  "sub": "9d3a8e98-91f5-41eb-b04b-222eb6720c86",
  "aud": "authenticated",
  "role": "authenticated",
  "is_anonymous": false,
  "email": "user@example.com",
  "phone": "+12025550100",
  "app_metadata": { "provider": "phone", "is_admin": false },
  "user_metadata": { "display_name": "Alex" },
  "aal": "aal1",
  "amr": [{ "method": "phone", "timestamp": 1781794127 }],
  "session_id": "edc2e2f1-…"
}
```

`sub` is Supabase's `auth.users.id` UUID, so your Zonai collection should use it as the primary key — that is what makes the lookup match without a mapping table.

Two shapes to expect. An anonymous session (`signInAnonymously()`) is identical except `is_anonymous: true`, empty `email` and `phone`, empty metadata maps, and `amr` naming the anonymous method. A phone-OTP session carries `phone` in E.164 and `email: ""`, because the SMS flow collects no address.

Anything you write into `app_metadata` at sign-up shows up here and is addressable from `adminClaimPath`.

## Provisioning a row

`SupabaseClaims.from(...)` decodes the standard fields into a typed shape, so the row builder is not a pile of `Object?` casts:

```dart in:extension-user
@override
Future<void> onExternalAuthFirstSeen(Map<String, Object?> claims) async {
  final supabase = SupabaseClaims.from(claims);
  mutate.create.one(
    tableName: tableName,
    object: <String, dynamic>{
      'id': supabase.sub,
      'email': supabase.email, // null for anonymous and phone-only users
    },
  );
}
```

It normalises the quirks that would otherwise each need a branch:

- **`sub` is required** — missing or empty throws `ArgumentError` rather than producing a row with no id.
- **`email: ""` is Supabase's "no email on file"** sentinel for anonymous and phone-only users. `email` returns `null` for both the empty string and the missing key.
- **`phone: ""`** normalises the same way.
- **`appMetadata` / `userMetadata`** arrive as `Map<String, Object?>?`, cast for you, `null` when missing or the wrong shape.

The hook's scope, the inline flush and the 30-per-hour default limit are the general external-IdP behaviour — see [Provisioning users](/authentication/external-idp#provisioning-users).

## Three things that will surprise you

**An anonymous token verifies exactly like a real one.** Same signature, same issuer, same `aud`. Only `is_anonymous` tells them apart, and nothing in the auth layer acts on it. If anonymous users should not be able to write, that belongs in a [row rule](/rules/row-rules) reading `claims['is_anonymous']` — not in this config, which will happily accept them.

**A service-role token would verify too.** Supabase's service-role JWT carries `role: "service_role"` with `aud: "authenticated"`, so it satisfies this config. Do not ship the service-role key to clients; and treat an inbound `role: "service_role"` as suspicious at the rule layer, because a token that reaches your server from a client is not one you issued to a server.

**Admin flags belong in `app_metadata`.** `user_metadata` is user-writable through Supabase's own client API. An `adminClaimPath` pointed there is a self-service admin button.

## Related

- **[External Identity Providers](/authentication/external-idp)** — the general mechanism, required claims, and what trusting an outside token costs.
- **[Row Rules](/rules/row-rules)** — where anonymous-vs-verified and service-role checks go.
- **[Config Flavors](/core-concepts/config-flavors)** — `.env` lookup and per-flavor secrets.
