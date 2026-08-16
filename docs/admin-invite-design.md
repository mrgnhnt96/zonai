# Admin invites — design and build plan

Status: **built**. Branch: `feat/oauth`. §7 records what landed and what did not.

Today an admin account can only be created from the CLI (`zonai db admin add`). The
dashboard shows an `Admin` badge and nothing else: `createAdmin`, `listAdmins` and
`removeAdmin` exist on `ZonaiDb` but have **no HTTP routes**, so no UI can reach them.

This adds admin management to the dashboard, with invites that are **accepted, not
granted**.

---

## 1. The decision that shapes it

`JwtConfig.isAdmin` is `admin != null` (`db_operations.dart:456`) — admin-ness is a
property of the **table**, not the row. Any row in an `AsAdmin` table gets an admin JWT.

So creating the row *is* the grant, and there is no "pending admin" state to model on the
row. An invite therefore must not create the row:

> **The invite is a pending record. The admin row is created at acceptance, and only when
> the accepting identity's verified email matches the invited address.**

That closes the failure this design exists to prevent: a mistyped invite going to a real
Google account cannot become an admin, because until someone accepts, no admin row — and
therefore no admin JWT — can exist for that address.

---

## 2. Where it lives

Invites reuse `_auth_challenges`, the table that already backs OTP, magic links, email
verification and password resets, with its expiry semantics, single-use consumption and
cleanup cron. A new `AuthChallengeType.adminInvite`:

| Field | Value |
| --- | --- |
| `target` | the invited email, lowercased |
| `table` | the `AsAdmin` collection |
| `secretHash` | `sha256(token)` — the raw token exists only in the email |
| `expiresAt` | now + 7 days |
| `allowedAttempts` | 1 |
| `userId` | null — there is no row yet, and that is the point |
| `metadata` | `{invitedBy, invitedByEmail}` for the audit trail |

Nothing new is needed in the schema layer beyond the enum value: `_oauth_identities` and
the challenge table already carry everything else.

---

## 3. Flows

### 3.1 Issue

`ZonaiDb.inviteAdmin({required String email, required String jwt})`

- Caller's JWT must be admin **on the resolved `AsAdmin` table**. Not "any admin".
- Refuse when a row with that email already exists — that person is already an admin.
- An existing live invite for the same email is **resent**, not duplicated (the same
  `isResend` shape `_sendMagicLink` already uses).
- Emits a `SendAdminInviteEmail` (`template: 'admin_invite'`) through `courier`, matching
  the existing `Email` subclasses in `libs/zonai_schema/lib/src/types/email.dart`, and
  registered in `initEmailTemplates`.

### 3.2 Accept — OAuth (the case that prompted this)

1. The email links to `{baseUrl}/_/admin/invite?token=…`.
2. That screen offers exactly the sign-in methods the admin table declares. For a
   Google-only table: one "Sign in with Google" button.
3. Starting OAuth from here carries the invite token into the `oauthState` challenge
   metadata, so the callback knows an invite is in play.
4. On callback, **before provisioning**: the provider's email must be verified and must
   equal the invite's `target`, case-insensitively. If it does not, refuse and leave the
   invite unconsumed — a different Google account must not burn someone else's invite.
5. On match: create the admin row, link the OAuth identity, consume the invite, sign in.

This is the one place `isAdmin` provisioning is allowed. `_resolveOAuthIdentity` currently
refuses provisioning outright when `isAdmin` (`oauth.dart:428`); an accepted invite is the
authorization that lifts it, for that email only.

### 3.3 Accept — password / OTP / magic-link tables

The same link, resolving to whatever the table supports: a set-password form for
`PasswordAuth`, or a bare accept for `OtpAuth` / `MagicLinkAuth` — no second code is sent,
because the invite link was already mailed to that address and holding it is the same proof
a magic link accepts. Same ending: row created, invite consumed, signed in.

Plus whatever columns the row cannot be created without (`name` on the reference schema),
which the probe reports as `fields` so the screen can ask before submitting rather than
discovering them from a failed insert.

Do not special-case OAuth so hard that the other three become impossible — the invite is a
property of the admin table, not of OAuth. The converse holds too: a table that declares
**only** OAuth is refused here rather than accepted on the weaker claim (see §7).

### 3.4 Revoke and remove

- **Revoke** a pending invite: set `canConsume = false`. The link stops working.
- **Remove** an admin: delete the row **and revoke their sessions**. An admin who is
  removed while signed in must not keep a working JWT until it expires.

---

## 4. Non-negotiables

Each needs a test that fails when the protection is removed.

1. Only an admin JWT for that table may invite, revoke, or remove.
2. Acceptance requires a **verified** provider email equal to the invited address.
3. A mismatched acceptance leaves the invite unconsumed and creates nothing.
4. The token is ≥128 bits, stored hashed, single-use, and expires.
5. A revoked or expired invite cannot be accepted.
6. **The last admin cannot be removed**, and an admin cannot remove themselves — a
   dashboard that can lock everyone out is a bug, not a feature.
7. Removing an admin revokes their existing sessions.
8. The raw token never reaches a log, an error message, or the swagger surface.
9. Invite issuance is rate limited.
10. Listing admins never returns password hashes or provider secrets.

---

## 5. Build plan

**W0 · `admin-invite-runtime`** — owns `apps/zonai/lib/src/db_mutator/**`, the new enum
value, and `libs/zonai_schema/lib/src/types/email.dart`.
`AuthChallengeType.adminInvite`; `inviteAdmin`, `revokeAdminInvite`, `listAdminInvites`,
and session revocation on remove; the invite-bound provisioning path in the OAuth callback;
`SendAdminInviteEmail`. Blocking — everything else builds on these names.

**W1 · parallel**
- `admin-invite-http` — owns `apps/server/**`. Routes for list / invite / revoke / remove,
  admin-authenticated, rate limited, swagger regenerated.
- `admin-invite-email` — owns the template in `initEmailTemplates` and the project
  `email_templates/` seed. Plain, brandable, no token in the subject line.

**W2 · parallel**
- `admin-invite-dashboard` — owns `apps/web/lib/**`. An Admins screen: current admins,
  pending invites with their expiry, an invite field, revoke and remove. Plus the
  `/admin/invite` acceptance screen, which must render the methods the table actually
  declares.
- `admin-invite-e2e` — owns `e2e/admin_invite/**`. Invite → accept → admin; wrong email
  refused; expired; revoked; non-admin cannot invite; last admin cannot be removed;
  removal revokes sessions.

**W3 · `admin-invite-docs`** — the walkthrough on
`apps/docs/content/authentication/admin-accounts.md`, including the Gmail-only path end to
end.

---

## 6. Known traps

| Trap | Handling |
| --- | --- |
| Crawlers in this campaign have twice closed a leaf without committing | Every brief says commit before closing; the orchestrator verifies the branch ref moved |
| `.game_loop/verify.yaml` in the main checkout carries rules for push-notification probe files absent from this branch, failing `check_verify_exemptions.sh` | Only fires for leaves touching `e2e/**`; do not bypass the gate — report and park |
| `apps/zonai/lib/gen` in a spawned worktree is a snapshot of another branch, and `analysis_options.yaml` hides it from `dart analyze` | Regenerate in-tree; only `dart test` catches a stale mirror |
| `revali dev --generate-only` has failed in some worktrees | Reported by one crawler, refuted by another; if it fails, say so rather than working around it |

---

## 7. Implementation status

Landed and tested: the runtime (`inviteAdmin`, `revokeAdminInvite`,
`listAdminInvites`, `startAdminInviteOAuth`, invite-bound provisioning, session
revocation on remove); the HTTP surface (`GET /admin/members`, `POST
/admin/invites`, `DELETE /admin/invites/:email`, `DELETE /admin/members/:email`,
rate limited); the `admin_invite` email template; the Admins screen and the
`/_/admin/invite` acceptance screen; runtime e2e and real-HTTP e2e, the latter
including the non-admin refusal that §4 item 1 needs.

Both gaps this section used to list are now closed.

**§3.3 is built.** `ZonaiDb.acceptAdminInvite` resolves the invite, creates the
row in the invite's *own* table, consumes the challenge and mints the session —
the same ending `_provisionInvitedAdmin` reaches for OAuth. `POST
/auth/admin/invite/accept` carries the token in the body rather than the query
string, because a query string reaches request logs, browser history and the
`Referer` of whatever renders next; `redactSensitiveQuery` is a mitigation for
the routes that have no choice, not a licence to put a credential there. The
acceptance screen renders a set-password form for `PasswordAuth` and a bare
*Accept invitation* button for `OtpAuth`/`MagicLinkAuth`.

Direct acceptance is authorized by the token **alone**, which is strictly weaker
than §3.2 — there a provider additionally vouches that the identity signing in
owns the invited address. So a table declaring OAuth and nothing else is refused
(`AdminInviteRequiresOAuthException`, 409) rather than offered a cheaper door.
Where the claim *is* right, it is the same one `MagicLinkAuth` already accepts:
the token was mailed to `target` and nowhere else.

Acceptance also collects the columns the row cannot be created without. The
reference schema's `User.name` is non-nullable, so a form that asked only for a
password produced a cast failure from the insert — the probe now reports those
columns as `fields`, resolved through the same `adminExtraCreateFields` helper
`zonai db admin add` uses, so the two surfaces cannot disagree about what an
admin row needs.

**The liveness probe exists.** `GET /auth/admin/invite?token=` answers
`{live, table, authTypes, fields}` without consuming anything, and answers
identically for expired, revoked, spent, forged and unknown tokens — in all
three layers independently (the runtime collapses them to one `null` and probes
every admin table regardless of what matched, so query count is not a side
channel; the handler maps that null to one shared const; the browser's parser
fails closed).

### The bootstrap gap, also closed

**Issuing an invite needed an admin session, so the first admin could not be
invited.** Closed by `zonai db admin invite` / `invites` / `revoke-invite`,
which go through `*FromCli` entry points taking no JWT. Deliberately separate
methods rather than a nullable `jwt`: a null meaning "root" on a method the HTTP
layer also calls is one missing argument away from an unauthenticated invite
route. CLI invites are attributed to nobody — an empty metadata map, not a
placeholder id — and skip the one-minute resend throttle, which is not a
boundary against a shell that can already write the table.

### Seeing the screens

Both dashboard screens render to standalone HTML without booting zonai:

```
cd apps/web && dart run tool/render_admin_screens.dart <out-dir>
cd apps/web && dart run tool/render_oauth_screens.dart <out-dir>
```

Five cases each in dark and light, chosen to show the decisions rather than the
happy path: the Admins screen with a pending invite and Remove disabled on your
own account; the sole admin, where Remove is disabled for the other half of §4
item 6; acceptance on a Google-only table; acceptance on a password-only table,
which explains itself and points at the CLI; and a link with no token.

The member and provider lists are supplied directly rather than fetched, so this
is not a substitute for running the binary. Everything downstream of them is the
real component tree, through the same `renderComponent` entry point
`main.server.dart` uses — which is what makes the output worth checking rather
than just looking at. Grepping the two acceptance renders for the raw token
returns zero hits in both branches, so "the token is never rendered" is
observed, not just intended.

### Owed to `.game_loop/verify.yaml`

`apps/web` grew from a handful of components to a 259-test suite during this
campaign, and `verify.yaml` still covers it with one single-file `dart analyze`.
Every `apps/web` path this campaign touched therefore committed as NOT CHECKED.
`dart analyze` cannot see any of what matters here: the Admins screen compiles
perfectly well with the wrong button enabled, and both §4 item 6 refusals are
held up by component tests alone — dropping the `refusal != null` guard fails
exactly those two tests and nothing else.

`.game_loop` is gitignored and belongs to the main checkout, so this cannot ride
the branch and is left for whoever owns that tree:

```yaml
"apps/web/lib/**":
  - "cd apps/web && dart test"
"apps/web/test/**":
  - "cd apps/web && dart test"
```
