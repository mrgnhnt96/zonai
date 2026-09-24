# Contributor docs

**Using zonai?** You want <https://docs.zonai.dev>, not this folder. Nothing here explains how to
build an app with zonai.

This folder is for people (and agents) changing zonai itself. Start with
[CONTRIBUTING.md](../CONTRIBUTING.md) for setup and the everyday commands.

## Working on the repo

| Doc | Read it when |
| --- | --- |
| [releasing.md](releasing.md) | Cutting a release, or touching a workflow the release depends on. |
| [known-issues.md](known-issues.md) | Something misbehaves and you want to know whether it's already understood. |
| [revali-dot-shorthand-codegen.md](revali-dot-shorthand-codegen.md) | Writing an annotation on a server controller. |
| [sqlite3-3x-migration.md](sqlite3-3x-migration.md) | Considering lifting the `sqlite3 <3.0.0` pin. |
| [docs-site/](docs-site/) | Changing how `apps/docs` is built, searched or deployed (the Jaspr Content playbook, API reference and GitHub Pages deployment). |

## Design records: `design/`

Why things are built the way they are. Code comments cite these by section (`§3.2`), so
they are kept and not rewritten. Each one has a status line at the top. They describe the design
at the time it was written, so **the code wins when the two disagree**. When a record cites a user
guide like `docs/auth.md` or `docs/push.md`, that guide now lives on the site
(`apps/docs/content/`).

| Record | Topic |
| --- | --- |
| [admin-invite-design.md](design/admin-invite-design.md) | Dashboard admin management and invites. |
| [api-tokens-design.md](design/api-tokens-design.md) | Non-expiring API tokens for the data API. |
| [force-password-reset-design.md](design/force-password-reset-design.md) | Operator-forced password reset on sign-in. |
| [oauth-design.md](design/oauth-design.md) | zonai running the OAuth/OIDC flow itself. |
| [oauth-internals.md](design/oauth-internals.md) | How OAuth works internally, and the test behind each security property. |
| [oauth-live-verification-handoff.md](design/oauth-live-verification-handoff.md) | How to re-run the live-provider OAuth check. |
| [push-design.md](design/push-design.md) | Push notifications (FCM/APNs). |
| [typed-client-design.md](design/typed-client-design.md) | `zonai gen client`. |
| [dart-sdk-skew.md](design/dart-sdk-skew.md) | Host binary and `.aot` workers built by different SDKs. |
| [stale-worker-guard.md](design/stale-worker-guard.md) | Detecting a stale worker before it crashes. |
| [linking-a-bare-released-binary.md](design/linking-a-bare-released-binary.md) | Why a bare released binary falls back to worker IPC (accepted, not fixed). |
| [build-fallback-next-steps.md](design/build-fallback-next-steps.md) | `zonai build` outside the monorepo (v0.6.1). |
| [testing-strategy.md](design/testing-strategy.md) | The release-gating test plan CI was built from. |
