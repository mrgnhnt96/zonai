# Supabase Auth as an external IdP

Practical end-to-end for trusting Supabase-issued JWTs in zonai. Sits
under the [external IdP](external-idp.md) walkthrough as the
platform-specific guide: where to look in the Supabase dashboard, which
claim shape to expect for verified vs anonymous users, and the
[`SupabaseExternalIdp`](../libs/zonai_schema/lib/src/integrations/supabase_external_idp.dart)
helper that wraps the URL boilerplate.

If your project also signs JWTs zonai-side (mixed auth), the patterns
on [external IdP](external-idp.md) still apply — this doc focuses on
the Supabase-only piece.

## When to use this

Pick this path when you've already invested in Supabase Auth (phone +
SMS OTP, anonymous sessions, social, magic link, etc.) and want zonai
as the data + rules + extensions + real-time layer in front of your
own SQLite. Supabase mints every JWT; zonai trusts those JWTs and
provisions a corresponding row in your zonai auth collection on
first-seen.

Common shape:

```
Flutter / web client
    ↓ Supabase Auth: sign in (phone OTP, anonymous, etc.)
    ↓ access_token
zonai server
    ↓ verify via JwksIdpConfig (asymmetric)  OR  SharedSecretIdpConfig (legacy)
    ↓ lookup authTable row by sub
    ↓ if missing → onExternalAuthFirstSeen provisions it
Profile row populated, request continues normally
```

## Asymmetric vs legacy HS256: which path do I want

Supabase shipped an asymmetric JWT model (ECC P-256, RS256, ES256) in
late 2025. Projects created after rollout default to this; older
projects keep the legacy HS256 shared-secret key until you rotate.

To check yours: **Project Settings → API → JWT Keys**.

- **Current Key shows `ECC (P-256)` / `RS256` / `ES256` / similar.**
  Use [`SupabaseExternalIdp.jwks(...)`](#asymmetric-jwks). zonai
  fetches the public key from Supabase's JWKS endpoint at runtime —
  **no secret in your config**.
- **Page shows only "Legacy HS256 (Shared Secret)" with no asymmetric
  Current Key.** Use [`SupabaseExternalIdp.sharedSecret(...)`](#legacy-hs256-shared-secret).
  Inject the HMAC secret as a compile-time `--define`; don't bake it
  in.
- **Both visible (project mid-rotation).** Prefer
  [`SupabaseExternalIdp.jwks(...)`](#asymmetric-jwks) — the legacy
  HS256 entry only verifies tokens minted before the rotation, and
  those expire on their normal TTL. New tokens are signed with the
  asymmetric Current Key.

A quick way to confirm without clicking through the dashboard: hit

```
https://<projectRef>.supabase.co/auth/v1/.well-known/jwks.json
```

A valid `{"keys":[...]}` body means asymmetric is active. A 404 (or
missing `keys`) means legacy-only.

## Asymmetric (JWKS)

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
    jwtSecret: const String.fromEnvironment('JWT_SECRET'),
    externalIdps: [
      SupabaseExternalIdp.jwks(
        projectRef: 'vshgjqqosbcoshzyznfq',
        authTable: 'profiles',
        adminClaimPath: 'app_metadata.is_admin',
        adminClaimEquals: true,
      ),
    ],
  );
}
```

What the helper does:

- Derives `issuer: 'https://<projectRef>.supabase.co/auth/v1'`.
- Derives `jwksUrl: '<issuer>/.well-known/jwks.json'`.
- Defaults `audience: 'authenticated'` (Supabase Auth's `aud` for both
  verified and anonymous user sessions).
- Validates `projectRef` is lowercase alphanumeric to catch the common
  "I pasted the full URL" mistake at startup, not at the first auth
  request.

The `adminClaimPath` / `adminClaimEquals` pair is optional. Supabase
puts service-role-writable claims under `app_metadata.*` by
convention; user-controlled claims live in `user_metadata.*` and
should never gate authorization. See
[Admin-claim mapping](external-idp.md#admin-claim-mapping) for the
underlying dotted-path semantics.

## Legacy HS256 (shared secret)

```dart
import 'package:zonai_schema/zonai_schema.dart';

AppConfig main() {
  return AppConfig(
    appName: 'My App',
    passwordSecret: const String.fromEnvironment('PASSWORD_SECRET'),
    jwtSecret: const String.fromEnvironment('JWT_SECRET'),
    externalIdps: [
      SupabaseExternalIdp.sharedSecret(
        projectRef: 'vshgjqqosbcoshzyznfq',
        authTable: 'profiles',
        secret: const String.fromEnvironment('SUPABASE_JWT_SECRET'),
        adminClaimPath: 'app_metadata.is_admin',
        adminClaimEquals: true,
      ),
    ],
  );
}
```

Grab `SUPABASE_JWT_SECRET` from **Project Settings → API → JWT Keys →
Legacy HS256 (Shared Secret) → Reveal**. Add it to `.env` (or the
flavor equivalent — `.env.dev`, `.env.prod`, etc.) in the same
directory as `zonai.yaml`:

```env
SUPABASE_JWT_SECRET=<hmac-secret>
```

`zonai compile` reads `.env` and passes each entry through to
`dart compile exe` as a `-D` define, baking the value into the worker
binary. See [config-and-env-flavors.md](config-and-env-flavors.md) for
the file-lookup rules and per-flavor overrides.

**`const` is load-bearing.** `String.fromEnvironment` (no `const`)
returns the runtime default at runtime instead of the compile-time
value. The helper accepts a plain `String`, but you should always pass
a `const String.fromEnvironment(...)` so the value gets baked into the
worker exe and isn't sitting on disk anywhere.

## Claim shape reference

Verified Supabase sessions carry the following claims (plus standard
JWT fields — `iss`, `aud`, `exp`, `iat`, etc.):

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
  "session_id": "edc2e2f1-..."
}
```

Anonymous sessions (`signInAnonymously()`) carry the same shape but:

```json
{
  "is_anonymous": true,
  "email": "",
  "phone": "",
  "app_metadata": {},
  "user_metadata": {},
  "amr": [{ "method": "anonymous", "timestamp": 1781794127 }]
}
```

Phone-OTP sessions (`verifyOtp(type: .sms)`) carry `email: ""` (no
email collected from SMS flow) and `phone: '<E.164>'`.

For the full claim catalog see
[Supabase Auth: Custom Claims](https://supabase.com/docs/guides/auth/auth-hooks/custom-access-token-hook)
— anything you put in `app_metadata` at sign-up surfaces here and is
addressable via `adminClaimPath`.

## Provisioning the row: `onExternalAuthFirstSeen`

The verification path resolves the JWT, looks up `authTable` by `sub`,
and — if the row's missing — calls your collection's
`onExternalAuthFirstSeen(claims)` extension. The claims map carries
the verified-by-signature payload; `SupabaseClaims.from(...)` decodes
the standard fields into a typed shape so you don't deal with raw
`Object?` casts in the row builder.

```dart
import 'package:my_app/src/schemas/profiles.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class ProfileProvisioning extends Extension<Profile>
    with AuthExtension<Profile> {
  ProfileProvisioning() : super(profiles);

  @override
  Future<void> onExternalAuthFirstSeen(Map<String, Object?> claims) async {
    final supabase = SupabaseClaims.from(claims);
    final now = DateTime.timestamp().toIso8601String();
    mutate.create.one(
      // tableName is inherited from Extension<Profile>; resolves to
      // 'profiles' here.
      tableName: tableName,
      object: {
        'id': supabase.sub,
        'email': supabase.email,           // null for anonymous
        'phone': supabase.phone,           // null when not collected
        'role': 'user',                    // default; admin via claim path
        'created_at': now,
        'updated_at': now,
      },
    );
  }
}

ProfileProvisioning main() => ProfileProvisioning();
```

`SupabaseClaims` normalizes a few Supabase-specific quirks:

- **`sub` is required**; missing or empty throws `ArgumentError`.
- **`email: ""` (empty string)** is Supabase's "no email on file"
  sentinel for anonymous and phone-only users. `SupabaseClaims.email`
  returns `null` for both empty and missing, so the row builder
  doesn't have to branch on both shapes.
- **`phone: ""`** likewise normalizes to `null`.
- **`app_metadata`** and **`user_metadata`** come through as
  `Map<String, Object?>?`; the cast is done for you, and `null` is
  returned when the claim is missing or the wrong shape.

The body of `onExternalAuthFirstSeen` runs under a
[ProvisioningJwt](external-idp.md#auto-provisioning-on-first-seen)
scoped to your `authTable`, so mutations queued via
`mutate.create.one(...)` insert that row even if your normal
row-rules would block end-user inserts. Mutations are flushed inline
before the auth pipeline re-fetches the new row.

## Gotchas

**Use v0.3.2 or later.** Older binaries can't generate migrations from
the compiled CLI. Generate migrations before serving, and the prebuilt
exe will apply them on startup. See zonai#12.

**Anonymous users always succeed in verification.** A Supabase
anonymous JWT verifies just like a phone-verified one — the signature
is the same; only `is_anonymous` distinguishes them. If your app
treats anonymous and verified users differently, gate that in your
row rules (e.g. `canCreate` rejects when `claims['is_anonymous']`),
not at the auth layer.

**Service-role tokens.** Supabase's service-role JWT carries
`role: "service_role"` and `aud: "authenticated"` — it would
*verify* through this config. Don't accept service-role tokens from
clients; treat any inbound `role: "service_role"` claim as suspicious
and reject at the row-rule layer. Better: don't ship the service-role
key to clients at all.

**Project ref vs project URL.** `projectRef` is the lowercase
alphanumeric prefix only (e.g. `vshgjqqosbcoshzyznfq`), *not*
`https://vshgjqqosbcoshzyznfq.supabase.co`. The helper validates this
at startup; the error message points at the right format.
