# Release notes

The short, human summary of each CLI release, newest first. `tool/ci/release_notes.sh`
turns the top section into the GitHub release description, and refuses to
publish a version this file does not describe — see docs/releasing.md,
"The release summary".

Keep it to what somebody deciding whether to upgrade needs: what they can now
do, and what stopped being broken. The commit list is already one click away.

## 0.10.0

**Upgrade `zonai_schema` to 0.6.0 and re-run `zonai compile`.** This CLI
requires it, and the security fixes below live in the schema your project
resolves. Then read the behaviour changes before you migrate.

- **Security: users can no longer verify themselves or change their own
  email.** The default user row rules let an owner change any column, so an
  app that allowed profile edits let a user set their own `is_verified` or
  swap in an address they never proved.
- **Security: counts no longer reveal rows the caller cannot see.**
  `/db/count`, a list's `total` and the count stream checked only the table
  rule. A count now covers only the rows the caller can view. A table whose
  row rules check each row must declare the new `viewScope` for counts to
  work at all, even if those rules allow every row. Otherwise `/db/count`
  answers `400 count_requires_view_scope`. If every row is visible, say so
  with `requiresPerRowCheck => false`, or scope to `NotNull('id')`.
- **Security: one account per address.** Auth tables now get the unique
  email index the docs always promised, emails are stored lowercased, and
  racing sign-ups (password, OTP or magic link) create one account.
- **Anonymous auth.** Create an account before its owner gives an address
  with `AnonymousAuth`, then upgrade it later and keep its id and data.
- **Safer updates.** `expect` makes an update apply only if the row is still
  what you read, and answers `412` otherwise. `$.revision(...)` adds a
  counter the server bumps on every write.
- **`zonai db migrate generate` refuses migrations that destroy data** unless
  you pass `--allow-destructive`. `--dry-run` warns about the loss too.
- **Fixes.**
  - Writes queued by `before*` hooks are saved instead of silently
    dropped.
  - Rules and hooks see a row's stored `created_at` / `updated_at`.
  - An unimplemented built-in email logs a warning instead of failing the
    request.
  - Email reaches a local SMTP catcher.
  - A malformed request body is a `400 invalid_body` instead of a `500`.
- **Behaviour changes.**
  - Before applying the migration that adds the unique email index, find
    addresses that differ only by case:
    `SELECT lower(email), count(*) FROM users GROUP BY lower(email) HAVING count(*) > 1;`
  - Signed-in users now see only their own user row by default. If your
    user row rules let users see each other, widen `viewScope` to match.
  - `Paginated.total` is `int?`: a list comes back without a total when the
    caller may not count every row.
  - Writes queued in `beforeSignUp` commit twice on OTP and magic-link
    sign-ups, so make them idempotent.
  - `beforeUpdate` now runs after the password-column check.
  - A table with a nullable email that isn't `AnonymousAuth` is refused at
    boot.
  - Flutter/FVM SDKs now get the Dart SDK check, so `zonai compile` and
    `zonai build` fail on a mismatched Dart. Switch SDKs, set `dartSdkPath`,
    or pass `--no-dart-sdk-check`.

## 0.9.4

- **Refreshing a session now only works for sessions zonai issued.** A token
  from an external identity provider could previously be exchanged at
  `refreshToken` for a zonai session; it is now refused.
- **Refresh finds the user by id, not email.** Refresh works on user tables
  without an email column, and a user whose email changed keeps refreshing.
- `zonai init` and the version check now require `zonai_schema` 0.5.0, and
  `zonai_client` 0.2.4 declares the same floor. Projects locked to an older
  schema get a clear upfront error instead of `migrate generate` crashing with
  "Unknown action: replay".

## 0.9.3

- **One server reaches development and production iOS builds.** Store a
  device's platform as `ios-sandbox` (new `DevicePlatform.iosSandbox` in
  `zonai_schema` 0.5.0) and it is sent to `api.sandbox.push.apple.com` with the
  same APNs key, beside `ios` rows going to production. Builds installed from
  Xcode or `flutter run` need it; TestFlight and App Store builds stay `ios`.
  `ApnsConfig.useSandbox` is now only the default host for `ios` rows.
- **A sandbox/production mismatch says so.** `BadDeviceToken` still clears the
  token, but its detail now names the host that refused it and the platform
  value that would have worked, instead of reading as a dead device.
- The dashboard's test send can target the APNs sandbox directly.

## 0.9.2

- **Push notifications are delivered.** Every earlier release with push failed
  each job before it reached FCM or APNs, logging `read(ScopedRef<PushCourier>)
  was called in a scope which does not contain a corresponding value`: the
  transports were never bound outside the test suite. That covered `push()`
  from hooks and crons, the `_drain_push_jobs` cron and the dashboard's test
  send. Jobs that failed this way stay failed — re-send them after upgrading.

## 0.9.1

- **Every refusal now tells a client when to come back.** A rate-limited `429`
  carries `retry-after` alongside `x-ratelimit-limit`, `x-ratelimit-remaining`
  and `x-ratelimit-reset`, and its body is now JSON naming the collection and
  operation that hit the limit. **If you match on the old plain-text body, key
  on the status code instead.** Both backpressure `503`s carry `retry-after`
  too. The one refusal that deliberately still does not is the email limiter,
  which does not know its own window and will not invent one.
- **A saturated read answers `503`, not `500`.** Through 0.9.0 a burst past the
  read-concurrency limit escaped uncaught and reached the client as an
  unclaimed `500` with no header and nothing useful in the body. It is now the
  same shaped refusal as the write side. Reaching it takes 256 genuinely
  concurrent reads, so most callers will never have seen it.
- **Writes survive concurrent load instead of collapsing.** A write now
  reserves its queue slot *before* the identity check and the password hash,
  and waits briefly for one instead of being refused the instant the queue is
  full. At 100 concurrent creates a release build went from ~82 successful
  writes a second with 98% refused to ~1100–3200 a second with none refused,
  and p99 latency fell from ~790ms to ~43ms. **The behaviour change worth
  knowing:** a write that used to fail immediately may now wait up to 250ms and
  then succeed. The cliff is moved rather than removed — capacity is 64 in
  flight plus 64 waiting, so a client past ~128 concurrent writes still meets
  backpressure, now with a `retry-after` to act on.
- **The server stops writing a stack trace for every refusal it authored.**
  Shedding load used to cost about six times more than serving a request,
  because each deliberate `503` formatted and printed a full trace — so
  saturation fed itself and a saturated sweep could put 40MB in the serve log.
  Fixed upstream in `revali_router` 5.1.2, which this release requires. If you
  parse the serve log, note that a released build now logs nothing for a
  refusal: an empty log is no longer evidence that nothing was refused.

## 0.9.0

- **Reclaim space on any database, not just the log.** The Maintenance card's
  "Reclaim log space" is now "Reclaim space", with a picker built from this
  deployment's real files and their real reclaimable bytes. Reclaiming the main
  database asks for its filename typed first, because a `VACUUM` there takes an
  exclusive lock on application data. `ZonaiDb.reclaimSpace` and `POST
  /dashboard/maintenance/reclaim-space` take the target and the floor; the old
  `reclaim-log-space` route stays, redirecting onto the new one and behaving
  exactly as it did.
- **`zonai compile` and `zonai build` refuse a mismatched Dart SDK.** They now
  exit 1 with a message naming both versions — "zonai was built with Dart
  3.13.2; you are on 3.12.0" — instead of producing workers that fail later at
  spawn. Every other command warns once and continues, and
  `--no-dart-sdk-check` turns the check off. This is the one thing here that can
  stop a command that used to succeed.
- Workers compiled by a Dart SDK that does not match the one zonai was built
  with are no longer loaded in-process. That combination could kill the running
  host outright with SIGABRT — no exception to catch, every in-flight request
  gone with it. The host now decides before the spawn and falls back to the
  worker process, which serves identically.
- `zonai compile` exits non-zero when a worker fails to compile. It used to
  report success on a project full of analyzer errors, and `zonai build` — which
  guards on that exit code — bundled whatever stale executables were already on
  disk.
- `zonai db migrate` and `zonai build` no longer die inside your project with
  `Couldn't resolve the package 'sqlite3'`. The vendored DDL driver reached
  `package:sqlite3` through an export chain nothing called; `zonai_schema` keeps
  that package a dev_dependency so a query-only client never has to resolve it.
- zonai is now built with Dart 3.13.2.

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
