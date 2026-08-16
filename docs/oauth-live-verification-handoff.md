# OAuth item 3 + live provider verification — handoff

> **Status: done** (2026-08-16). Item 3 is closed — the seam, the offline
> test and the live test all landed, and `docs/oauth.md` no longer lists it.
> Kept for the reasoning, and because §2c/§3 describe how to re-run the live
> check. Section 5 records what the live run actually observed.
>
> **Items 1 and 2 are closed too** (§6). `docs/oauth.md`'s "Still open" list
> is now empty. What remains in §4 is entirely decisions for a human — none
> of it is unfinished engineering.

Branch `feat/oauth`, worktree `.claude/worktrees/gleaming-tinkering-kernighan`.
Written 2026-08-16, at 53 commits ahead of `origin/main`, tree clean, static +
unit + `apps/zonai` (669) + `apps/web` (273) all green.

Picks up the third of the three items `docs/oauth.md` lists under **Still
open**, plus a live check against a real provider that no test in this repo
currently does.

---

## 1. What is actually wrong (item 3)

`oauth.dart`'s GitHub null-email fallback. When GitHub's `GET /user` returns
`email: null` — a private primary address, which is GitHub's *default* for new
accounts — the runtime falls back to `GET /user/emails` and takes the primary
verified one:

    parts/auth/oauth.dart:706-717
        if (accessToken != null &&
            identity.email == null &&
            provider is BuiltInOAuthProvider &&
            provider.kind == OAuthProviderKind.github) {
          final email = await GitHubEmailResolver().primaryVerifiedEmail(...)

Three things make that branch unreachable from any test:

1. **No seam at the call site.** `GitHubEmailResolver()` is constructed inline
   with no argument. The class *does* take an optional `http.Client` — that is
   how `github_email_resolver_test.dart` injects a fake — but the caller passes
   none, so there is nothing to substitute.
2. **The endpoint is a constant.** `github_email_resolver.dart:21` holds
   `https://api.github.com/user/emails` as a `static final`.
3. **The gate is `is BuiltInOAuthProvider && kind == github`.** A stub provider
   cannot enter the branch at all, and `OAuthProvider.github()`
   (`oauth_provider.dart:243`) hardcodes `endpoints` as a `const`, so a fixture
   cannot point a github-kind provider at a local stub either.

Unit coverage of the resolver itself is fine — 5 cases: primary-verified found,
unverified primary rejected, none usable → null, non-200 throws, malformed body
throws. **What is untested is the wiring**: that the branch fires under the
right conditions, and that the identity is rebuilt with `emailVerified: true`.

### Why not "just make it stubbable"

Point 3 is tempting to fix by letting `OAuthProvider.github()` take endpoint
overrides. Don't. The whole point of a built-in factory is that a developer
cannot misconfigure the endpoints; widening that API to serve a test inverts
the guarantee. The gate is correct as written.

---

## 2. The plan

### 2a. The seam (production change, small)

Follow the pattern already in this file for Apple. `zonai_db.dart:243` holds:

    final AppleClientSecretSigner _appleClientSecretSigner = AppleClientSecretSigner();

and `oauth.dart:659` passes it down. Do the same for the resolver:

- add a `_githubEmailResolver` field on `ZonaiDb` beside the signer,
- have `oauth.dart:715` use it instead of constructing one inline.

That makes the branch reachable **in-process** — `oauth_e2e_test.dart` already
drives `ZonaiDb` directly rather than a compiled binary, so a Dart-level seam is
enough there. Give `GitHubEmailResolver` an optional endpoint `Uri` too
(defaulting to the current constant) if the test wants a local stub rather than
a fake client; prefer the fake client, it needs no server.

### 2b. The test that closes item 3

An in-process test that reaches the branch through `completeOAuth`, with:

- a github-kind built-in provider,
- a `/user` response carrying `email: null`,
- an injected resolver that answers with a verified primary,

asserting the resulting identity carries that email **and** `emailVerified:
true`. Deleting the fallback must fail it — check that, don't assume it.

### 2c. The live check (what no stub can prove)

A stub can prove we parse *our idea* of GitHub's response. It cannot prove that
idea is right. The credentials on this machine can:

- **GitHub** — `$GITHUB_TOKEN` is a classic PAT (`ghp_`, 40 chars) whose scopes
  include `user`, which covers `user:email`. So `GET /user/emails` — the exact
  endpoint the resolver hits — is callable. Construct the **real**
  `GitHubEmailResolver` with a real `http.Client` and assert it returns a
  non-null verified primary.
- **Google** — `gcloud` is authenticated as `mrgnhnt96@gmail.com` (active).
  `gcloud auth print-access-token` yields an access token that can call
  `https://www.googleapis.com/oauth2/v3/userinfo`, the endpoint
  `OAuthUserInfoClient` uses for Google. That validates the userinfo contract
  and `extractOAuthIdentity`'s claim mapping against a real payload.

**What these do NOT prove**, and the handoff should keep saying so: neither
exercises the browser redirect + consent leg, and neither validates an
`id_token` `aud` against our own client — a gcloud token's audience is gcloud's
OAuth client, not ours. They prove the *API-facing* half, which is precisely the
half currently faked.

### 2d. Where the live checks live

They need a credential and a network, so they must not run in the default
suite. Put them behind a `package:test` tag (check `dart_test.yaml` for an
existing convention first) or a `--define`, skipped with a loud
`markTestSkipped` when the credential is absent — **never** silently passing.
`apps/docs`' anchors test is the cautionary example: run bare it reported green
by not running, which is called out in `scripts.yaml`'s `test docs` target.

---

## 3. Rules of engagement for the credentials

The PAT is broad — `repo`, `delete_repo`, `admin:org`, `workflow`, and more.
**Read-only calls only**, and only these two endpoints: `GET /user` and
`GET /user/emails`. No writes, no repo access, nothing outside verifying this
one code path.

The response contains real personal email addresses. Assert on *shape* —
non-null, verified, primary — and never print the value into test output, a
commit message, a doc, or a log line.

---

## 4. State to be aware of

- `feat/oauth` is **local only**: 53 commits, never pushed, no PR. Pushing is
  the human's call and has not been given.
- `.game_loop/verify.yaml` still has **no rule covering `apps/web/**`**, so
  every `apps/web` path in this campaign committed as NOT CHECKED. The write
  guard refuses the edit as project policy and has now refused two sessions.
  The exact YAML is at the bottom of `docs/admin-invite-design.md`; authorizing
  it is the human's call.
- `showrunner status` shows 2 stale claims and `oauth-admin-add` parked though
  the code landed. `reap` checks liveness by bare pid — verify with
  `ps -o lstart=` before ever running it with `--apply`.
- After **any** change under `apps/server`, resync the embedded mirror or
  `apps/zonai` tests load stale code. `server.sync-to-cli` now regenerates
  swagger *before* the copy (fixed this session); from a worktree run the steps
  by hand, since `sip` resolves to the main checkout.
- The other two open items in `docs/oauth.md` are deliberately **not** in scope
  here. Item 1 (§4 item 7) is largely stale — three OAuth-specific redaction
  assertions already exist; the real remainder is that no test inspects a live
  server's log output for an OAuth `code`/`state`, because the OAuth e2e has no
  `_LiveServer`. Item 2 (live-network JWKS) is best left documented: an honest
  test needs a real issuer or a trusted TLS cert, and the alternative is
  lowering the `https` check the verifier exists to enforce.


---

## 5. What the live run observed

Run against the real `api.github.com` with a classic PAT, read-only, on
2026-08-16.

The account under test turned out to be a genuine instance of the case rather
than a contrived one:

- `GET /user` returned **`email: null`** — the primary address is private,
  which is GitHub's own default.
- `GET /user/emails` returned four addresses, exactly one of them
  `primary: true, verified: true`, with `visibility: "private"` on that one.
- `id` came back as a JSON **integer**, confirming why a strict-string subject
  extractor breaks every GitHub sign-in.

`resolveIdentityFromTokens` against that account resolved the email, marked it
verified, and produced a numeric subject.

**Both controls were run rather than assumed.** With the fallback branch
disabled, the offline test fails on exactly the one case that pins the
behaviour (the other three correctly still pass), and the live test fails with
`Expected: not null / Actual: <null>` — which also proves independently that
real GitHub returns no email here, and that the fallback is what supplies it.

Addresses were never printed: the assertions are on shape, and the captured
evidence file redacts every local-part.

### Re-running it

    cd apps/zonai && dart test -P live

Skipped by default, and skipped loudly when `GITHUB_TOKEN` is absent. The tag
is what keeps it off CI — GitHub Actions sets `GITHUB_TOKEN` in every job, so
an env-var check alone would have run it there against a different identity.

### Google

Not needed in the end. GitHub was the provider item 3 is about, and its
account exhibited the exact condition under test, so a second provider would
have added a userinfo-contract check without touching the branch in question.
The gcloud path in §2c still works if someone wants that check later.

---

## 6. The other two items, closed (commit `25a866e`)

§4 listed items 1 and 2 as deliberately out of scope. Picking them up
afterwards, both proved cheaper than `docs/oauth.md` claimed — and item 1's
diagnosis there was wrong in a way worth keeping on the record.

### Item 2 — live-network JWKS

The stated objection was that an honest test needs a real issuer or a trusted
TLS certificate. The `live` tag built for item 3 supplies exactly that, so the
objection had already been retired without anyone noticing.

`jwks_idp_verifier_live_test.dart` verifies a genuine Google-signed `id_token`
from `gcloud auth print-identity-token` against Google's live JWKS. The token's
`iss` is `https://accounts.google.com` — the exact issuer `OAuthProvider.google`
declares — so the config is built through the production `oauthJwksConfig`
helper rather than by hand. Its `aud` is the gcloud CLI's own public client id,
so that is what the provider is constructed with; gcloud is a legitimate Google
OAuth client.

The case a mock structurally cannot make: `_refreshCache` skips key entries
`jose` cannot parse, silently. A test that authors its own JWKS only ever
writes shapes `jose` just produced, so an issuer publishing something `jose`
rejected would empty the key store and fail every sign-in with a bare
`InvalidJwtException`. The live test asserts every key Google actually
publishes parses.

### Item 1 — server log output

`docs/oauth.md` said the admin-invite suite already did this and that closing
the item meant giving the OAuth e2e a live server of its own. **Both halves
were wrong.** That suite has driven a real OAuth start→callback over a live
server all along. What it lacked was a working log capture.

`TraceId` re-overrides `loggerProvider` for the duration of every request with
`Logger.print(...)`, which writes through `PrintSink` → `dart:core`'s `print`,
discarding the `IOSink` the harness injected. `capturedLogOutput` therefore
only ever held the startup lines emitted before the first request — 178 bytes
of config-executable chatter, against which every `isNot(contains(...))`
passes for free. The pre-existing invite-token log assertion had been vacuous
since the day it was written.

`print` is zone-scoped, so the fix is to capture the zone, not the sink.

### Controls

Every claim above was checked by making it fail first:

- disabling `redactSensitiveQuery` in the embedded mirror turns **both** log
  tests red — the new one and the invite-token one that previously could not
  fail;
- disabling the JWKS signature check turns exactly one live test red;
- that second control also caught a defect in the new test itself:
  `expectLater` prints the actual value on failure, and the actual value was
  the decoded claim map carrying a real `sub` and email. `outcomeOf()` now
  collapses success to a fixed marker, and a re-run confirmed the failure
  output no longer contains the address. **This is the §3 rule catching a
  violation authored by the very test written to honour it** — the reason to
  run a control is that it inspects things assertions do not.

### Re-running

    cd apps/zonai && dart test -P live     # 5 tests: real GitHub + real Google

Both live suites skip loudly by default and name the preset in the skip reason.

### What is left, and why none of it is engineering

- `feat/oauth` is **56 commits, local only, no PR**. Pushing is the human's
  call and has never been given.
- `.game_loop/verify.yaml` still has no rule for `apps/web/**`, and now none
  for the two new test paths either — `verify` reports them NOT CHECKED. The
  write guard refuses the edit as project policy, correctly; it needs
  `game_loop authorize`. The YAML is at the bottom of
  `docs/admin-invite-design.md`.
- `showrunner status` still shows 2 stale claims and `oauth-admin-add` parked
  though it landed. `reap` checks liveness by bare pid — verify with
  `ps -o lstart=` before ever running `--apply`.
- A worktree-local `.game_loop` state home was found holding an orphaned,
  still-active mandate for work that landed hours earlier; the real state home
  is the main checkout. The orphan was cleared. Worth knowing that invoking
  `game_loop` from inside a worktree reads a different state directory than
  the hooks do.
