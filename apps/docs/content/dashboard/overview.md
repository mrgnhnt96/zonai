---
title: Dashboard Overview
description: The built-in admin UI at /_ — traffic metrics, cron jobs, and a full table browser and editor.
---

Every Zonai server serves a web dashboard at **`/_`**. It is compiled into the
binary alongside your API, so there is nothing extra to install, deploy, or
run — start the server and open it in a browser.

```bash
./zonai serve
# Access the UI at http://127.0.0.1:8080/_
```

The dashboard gives you two things: a look at what the server is doing
([Metrics & Cron Jobs](/dashboard/metrics)), and a way to read and change rows
without writing a query ([Browsing & Editing Data](/dashboard/table-editor)).

## Signing in

The dashboard authenticates against **your own auth table** — the same
credentials your app's users have. Whichever methods your table mixes in are
what the sign-in screen offers: password, one-time passcode, or magic link.
Password reset and email verification are handled in the UI too.

<Warning>

**You need an admin account.** Signing in as an ordinary user is not enough —
the dashboard's data is gated on the `isAdmin` claim in your JWT, and a
non-admin session is rejected.

Create one with [`zonai db admin`](/cli/db), and see
[Admin Accounts](/authentication/admin-accounts) for how the `AsAdmin` trait
and the elevated claims work.

</Warning>

## Where it lives

Every screen sits under the `/_` prefix, which keeps it clear of your API
routes:

| Path | Screen |
| --- | --- |
| `/_` | [Metrics and cron jobs](/dashboard/metrics) |
| `/_/tables` | Table list |
| `/_/tables/<table>` | [Row browser and editor](/dashboard/table-editor) |
| `/_/sign-in` | Sign-in |

## Settings

The account menu holds **Account** details, **Admin** options, an
**Appearance** control for light and dark themes, and **Sign out**.

## In production

The dashboard is part of the server, not a development-only extra: a binary
from `zonai build` serves `/_` exactly as `zonai serve` does. There is no flag
that turns it off.

That is convenient, and it is also worth thinking about before you expose a
server to the internet:

- **Admin accounts are the only thing standing in front of it.** Treat those
  credentials as production secrets, and prefer OTP or magic-link sign-in over
  a shared password.
- **Consider not exposing `/_` publicly at all.** If your deployment sits
  behind a reverse proxy, blocking or IP-allowlisting the `/_` prefix there
  leaves your API reachable while keeping the dashboard private. Reaching it
  over an SSH tunnel to the host is another option.
- **Rate limits still apply** to the endpoints the dashboard calls, so a
  brute-force attempt against admin sign-in is throttled like any other auth
  traffic. See [Auth Rate Limits](/rate-limiting/auth-rate-limits).

## Related

- [Metrics & Cron Jobs](/dashboard/metrics) — what the landing screen reports
- [Browsing & Editing Data](/dashboard/table-editor) — the table UI
- [Branding](/dashboard/branding) — replacing the favicon and logo
- [Admin Accounts](/authentication/admin-accounts) — creating the account you sign in with
- [Server Binding](/deployment/server-binding) — which interface the server listens on
