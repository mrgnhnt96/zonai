# Known issues

Only issues that are still open are listed here. Fixed ones are removed and kept in git history (`git log -p -- docs/known-issues.md`).
Numbers are stable. Code cites them, so a number is never reused and gaps are expected.

## 14. `ZONAI_FORCE_WORKERS=1` never starts under `dart run`

**Symptom.** Under `dart run`, `zonai serve` with `ZONAI_FORCE_WORKERS=1` polls
health 200 times, logs `Unexpectedly failed to make connection to Revali
(server)`, and exits. No `[CONFIG_EXE]` line appears. Compiled binaries are not
affected, so nothing shipped is broken. But the env var is documented as the
way to exercise the worker path, and in dev it cannot be used.

**Reproduce**, from `apps/playground`:

```
dart run ../zonai/bin/zonai.dart serve --no-version-check                        # serves
ZONAI_FORCE_WORKERS=1 dart run ../zonai/bin/zonai.dart serve --no-version-check  # hangs, then dies
```

**Cause.** Three decisions combine to produce it:

1. `resolveProjectLink` returns `ProjectLink.skip('$kForceWorkersEnv is set')`,
   so the generated project entry is never run
   (`apps/zonai/lib/src/domain/project/project_link.dart:84`).
2. `maybeReexecProjectRuntime` returns early on `forceWorkers`, so
   `HostWorkerRegistries.operations` is never assigned
   (`apps/zonai/lib/src/domain/project/project_runtime.dart:63`).
3. `Revali._inProcessHttp` is `kIsCompiled || HostWorkerRegistries.hasOperations`
   (`apps/zonai/lib/src/db_mutator/revali.dart:22`). Both are false, so the
   server goes to `_startDebug`, which shells out to `dart run revali dev` and
   gives up after 20s.

The generated entry already guards its registry assignment with
`if (!HostWorkerRegistries.forceWorkers)`
(`apps/zonai/lib/src/domain/project/project_generator.dart:31`). It was written
to run under force-workers, but (1) means it never runs. That conflict is the bug.

**Workaround.** Use a compiled binary
(`ZONAI_FORCE_WORKERS=1 ./zonai serve --release`).

**Fix direction.** Stop `forceWorkers` from suppressing the project link, and
let the entry's existing guard leave the registries empty. The fallback is to
decouple `_inProcessHttp` from `hasOperations`. To verify a fix, the repro
should log the `[*_EXE]: Started` lines and answer a request end to end.
Binding the port is not enough, because that part already works.

## 7. CORS preflight still reflects any `Origin` with credentials

The original gap, no CORS support at all, is fixed. The `@Cors()` lifecycle
component (`apps/server/routes/apps/dev_app.dart`) allows loopback origins plus
`ZONAI_ALLOWED_ORIGINS`, and it strips `Access-Control-Allow-Origin` and
`-Allow-Credentials` from real responses sent to any other origin. What is left
is the preflight.

**Symptom.** Send `OPTIONS` with `Origin: https://evil.example`. The response
carries `Access-Control-Allow-Origin: https://evil.example` and
`Access-Control-Allow-Credentials: true`. The actual request that follows is
stripped by `Cors.wrap`, so a hostile page cannot read any response. The
preflight still grants something it should not.

**Where.** revali_router 5.1.2, `RunOriginCheck.run` (`run_origin_check.dart`).
With an empty allow-list it reflects any `Origin` and always sets
credentials `true`. `RunOptions` returns that response before any middleware
runs, so no app-level component can reach it. `apps/server/test/cors_policy_test.dart`
states that it does not cover this path.

**Workaround.** None needed for data safety, because the real response is
stripped. A reverse proxy can answer or filter `OPTIONS` if you need a clean
preflight.

**Fix direction.** Upstream in revali_router: do not reflect an unmatched
origin, and do not set credentials unless the origin matched. Alternatively,
run middleware on preflights.

## 6. `AsAdmin` makes every row of the table an admin

**Symptom.** Every JWT issued for any row in an `AsAdmin` table carries
`admin.isAdmin: true`, whether it came from sign-up, sign-in, OTP or magic
link. There is no per-row admin flag, so admin and non-admin accounts cannot
coexist in one auth table.

**Where.** `DbOperations._getJwtConfig` and `_getTableAdminStatus`
(`libs/zonai_schema/lib/src/handlers/operations/db_operations.dart`) both
compute `isAdmin: admin != null` from the table's schema only.

**What is mitigated.** `AuthRowRules.canSignUp` returns `false` on an
`AsAdmin` table unless the caller already holds an admin token
(`libs/zonai_schema/lib/src/rules/row/auth_row_rules.dart:45`). A table that
overrides `canSignUp` to allow sign-up therefore makes every registrant an
admin. `zonai db admin create` bypasses rules and is unaffected.

**Workaround.** Put `AsAdmin` only on a dedicated admin table that is populated
through `zonai db admin add`, and keep your user table separate. This is
documented on the docs site (`apps/docs/content/rules/jwt-claims.md`).

**Fix direction.** Make `isAdmin` a real per-row column or claim. This is an
invasive design change.

## 3. Most `implements Id` classes have identity equality, not value equality

**Symptom.** `Id` (`libs/zonai_schema/lib/src/types/id.dart`) defines
`operator ==` and `hashCode`, but `implements` does not inherit method bodies.
An implementer without its own override falls back to `Object` identity, so
two instances built from the same string compare unequal. `UnknownId`,
`ApiTokenId` and `PushJobId` have their own overrides. These do not:

- `JwtId` (`types/jwt_id.dart`)
- `AbuserId`, `OAuthIdentityId`, `AuthChallengeId`, `LogId`, `PhotoId`,
  `PasswordResetRequirementId`, `CronsId`, `RateLimitId`
  (`internal/tables/*_table.dart`)

**Where it bites.** It is latent today. These ids are used as keys and SQL
query values, which compare the column value in SQL rather than with Dart `==`.
The first direct `==`, `Set` or `Map` use on one of them becomes a real bug.
That is how it bit `UnknownId` in `PhotoRowRules`.

**Workaround.** Compare `.value`, not the id objects.

**Fix direction.** Give each class the same `==`/`hashCode` override, or move
them onto a shared base with `extends` or a mixin. Test with non-`const`
instances, because `const` literals are canonicalised and pass through
identity (see `libs/zonai_schema/test/src/types/id_test.dart`).
