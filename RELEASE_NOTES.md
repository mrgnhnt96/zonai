# Release notes

The short, human summary of each CLI release, newest first. `tool/ci/release_notes.sh`
turns the top section into the GitHub release description, and refuses to
publish a version this file does not describe — see docs/releasing.md,
"The release summary".

Keep it to what somebody deciding whether to upgrade needs: what they can now
do, and what stopped being broken. The commit list is already one click away.

## 0.8.5

- The dashboard's "Most sessions" list is clickable — each user opens the same
  row-detail panel the tables screen opens, instead of printing an id to copy.
- Long tooltips stay inside the window. They wrap at their authored newlines,
  flip on both axes, and measure their real box rather than a hardcoded 44px.
- The dashboard scrollbar sits flush against the right edge of the viewport
  instead of 20px in from it.

## 0.8.4

- **API tokens.** A credential that needs no sign-in: `zonai db token
  create/list/revoke/delete` talks to the database file directly, `/admin/tokens`
  mints one over HTTP, and the dashboard has an API tokens screen (and a
  mint-a-bound-token action on an auth row's panel). Tokens are scoped to
  tables and operations, admin unless told otherwise, stored as a SHA-256, and
  record when they were last used.
- **Forced password reset.** An account can be made to owe a new password —
  from `zonai db`, from the server, and from the dashboard's own door. A
  password sign-in that owes one is refused with a `403
  password_reset_required` envelope, pinned in the swagger and typed in the
  client as `PasswordResetRequiredException`.
- **`beforeSignUp`.** `AuthExtension` can now decline a sign-up instead of only
  being told one happened, and the gate runs before the OTP and magic-link
  email rather than after.
- **Push from the dashboard.** Select rows in a table with a device-token
  column, compose one notification, and send it to every selected device.
- **`zonai ai update`.** Refreshes the reference files a project already has —
  which are version-stamped now, so a stale one is visible — without installing
  files for tools it never asked for.
- Fixes: the reads connection got the `busy_timeout` everything assumed it had;
  `POST /auth/confirm` is rate-limited; a disposed mailman worker no longer
  turns a dropped reply into a 10-second hang; a fire-and-forget email send owns
  its failure; a row's password reset goes to that row's own table; two
  conditionally-rendered auth components no longer break their own teardown;
  and the web build recovers from a stale asset graph instead of dying.
- `zonai_schema` 0.4.2 on pub.dev, with the changelog owed since 0.4.1.
