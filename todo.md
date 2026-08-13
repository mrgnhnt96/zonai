# TODO

## 6.1.26

- [x] ~~When we have more credits, we need to verify the release process, everything passes except for windows atm~~ Verified end to end on 2026-08-11 with the v0.6.1 release. Windows passes: `Verify Release` run `31444744628` was 15/15 green including `zonai-windows-x64`, and `Release` run `31558446442` published v0.6.1 with all 11 assets. Along the way the release process turned out to be broken in three separate places by the `zonai_schema-v*`/`zonai_client-v*` package releases taking GitHub's "latest" slot — see `docs/build-fallback-next-steps.md`.
- [ ] `--check` on the native-library builders only tests that the library *exists*, not that it's current, so a resqlite pin bump or argon2 builder change silently ships a stale library. Not biting yet (the cache postdates both). See `docs/build-fallback-next-steps.md` for the three options weighed; recommendation is a `fresh_native_libs` dispatch input now, a real staleness stamp later. Note `native-libs.yml` artifacts expire ~2026-10-30, after which every compile silently falls back to source builds.
- [x] ~~Real deployments still get worker IPC rather than in-process ops/rules... The merged-`package_config` route is proven to work but unbuilt~~ **Built and shipped in v0.6.1** (`resolveProjectLink()` in `domain/project/project_link.dart`, zonai-wins merge; `docs/build-fallback-next-steps.md` §2). Any project with zonai's sources reachable now links — which includes override_canvas's Docker build. Do not re-plan this.
- [ ] A **bare released binary** still falls back to worker IPC, and structurally always will: with no zonai sources on disk there is no second graph to merge. Weighed 2026-08-12 and **accepted rather than closed** — the only route (vendor zonai's whole 58-package, 21.8 MB source closure into the binary and self-extract it) buys unmeasured dispatch cost plus fine-grained per-operation rate limiting, and costs a frozen dependency closure that drifts from the project's own resolution for the life of each release. Revisit if the dispatch cost gets measured and matters. See `docs/linking-a-bare-released-binary.md`, which also retracts the claim that this was what made the stale-worker guard inert (it was `kIsCompiled`, independently — `project_runtime.dart:58`).
- [ ] When creating a new record that uses a foreign key, if the foreign key is an object, we should create the object first and then use the id to create the original record
- [x] ~~Fix the `get.*`/`addClaims` reentrant-IPC deadlock~~ Fixed in `5251cba` (`Mailman._send` split into a serialized write step and an unserialized await, so a reentrant nested send no longer queues behind its own outer request). See `docs/known-issues.md` #8's 2026-07-26 update for the real root cause (host-side `Mailman`, not worker-side `MessageHandler` as first suspected) and how it was verified. Confirmed downstream in override_canvas: `OrganizationRowRules`/`ClientAppRowRules`/`RecordingRowRules` now call `get.*` from inside `canView` for real, live collaborator-access checks, with the full integration suite (72 tests, `dart test --concurrency=2`) green and stable across repeated runs.
- [x] ~~`zonai serve` dies on its own after a short idle gap between requests~~ Reclassified 2026-07-26, likely not a zonai bug — see `docs/known-issues.md` #9's update. Couldn't reproduce as a real application defect (several minutes of idle/polling/real traffic against the actual compiled binary, no crash); the one death caught went straight into `Kill.force()`'s signal-driven shutdown sequence, not this entry's `_checkHealth`/health-check-exhausted symptom. override_canvas's own `todo.md`, same session, independently noted backgrounded `zonai serve` processes dying between separate shell-tool invocations for unrelated-to-zonai reasons — matches. Leaving the original write-up in known-issues.md as-is in case it still reproduces for someone in a real terminal session.
- [x] ~~No CORS support~~ Fixed as of 2026-07-26 — confirmed via a real preflight (`OPTIONS /db`/`OPTIONS /db/list`) against the compiled `apps/server` binary returning proper `access-control-*` headers for a cross-origin caller, and override_canvas's `apps/website` (a genuinely separate origin from its server) signing in successfully through a real browser. See `docs/known-issues.md` #7's update.
- [x] ~~`POST /auth/reset-password` crashes with an uncaught `scoped_deps` error (`read(ScopedRef<_Logger>)`...) instead of the graceful warn-and-skip `docs/email.md` promises, whenever `AppConfig.email` isn't set~~ Fixed 2026-08-12, and the original diagnosis was wrong twice over. The crash had already stopped happening on 2026-07-31: `9054cf0` gave `zonai_schema`'s worker-side logger a no-op `orElse` as a side effect of unrelated work, so the branch went from crashing to *silent* — the same defect, harder to diagnose, since every `courier.send` caller is fire-and-forget. And the scope was never missing: `courier.dart` imported the `zonai_schema` barrel, which re-exports the worker-side `logger` without hiding it, so `logger.warn` was resolving to the wrong logger entirely. Fixed by importing the barrel `hide logger` plus `../deps/logger.dart` (matching `mailman.dart`/`zonai_db.dart`), with `loggerProvider` added to `ZonaiDb._run`/`_runStream`'s `includeIfAbsent` so the real logger can never be absent on that path. See `docs/known-issues.md` #10; coverage in `apps/zonai/test/src/email/courier_test.dart` asserts the warning text, not just "does not throw". **Open question for override_canvas:** this entry claimed the forgot-password UI was blocked, on the strength of the crash — the crash has been gone since 2026-07-31, so the flow may already work; nobody has checked.
- [x] ~~`Jwt.parse` throws instead of returning `null` for a malformed token~~ Fixed 2026-07-26 — wrapped the decode/`Jwt.fromJson` steps in a `try`/`on Object` matching the existing `Jwt.maybeFromJson` pattern. Found while reviewing `Jwt.parse` right after the adjacent base64url-padding fix in the same method. See `docs/known-issues.md` #11; new coverage in `libs/zonai_schema/test/src/types/jwt_test.dart`.

### UI

- [ ] Add theme color support
- [ ] Pin collections (?)
- [ ] Add search history
- [ ] Support user defined favicon
- [ ] When clicking on an error in the dashboard, open the trace in the logs table
- [ ] Add icon for "filter" in the row details panel next to each field. Will auto apply "column=..." filter
- [ ] Support custom favicon

- [ ] Improve the "references" experience
  - [ ] List all references in tables & rows
  - [ ] Delete all references from rows (delete rows?)
  - [ ] What happens when you try to delete a row that is referenced by another row?

### API

- [ ] Create references to photo from other collections when using the `photo` or `photos` column
- [ ] Add prefix & suffix positional optional params to Id.generate
- [ ] When logging 400+ response codes use warning color
- [ ] When logging 500+ response codes, use error color

## CLI

### `dev` command

- [ ] Make the init (within `dev`) command more interactive

## Raindrop

- [ ] Add feature to alert/fail on breaking changes
- Investigate how to handle base classes for schemas & extending them
- [ ] Add support for one to many relationships
- [ ] Investigate an optional `attach` capability on tables — or on "table groups" — letting a table declare that it lives in its own database file rather than in `zonai.sqlite`, joined back through SQLite's `ATTACH` so it stays queryable through the normal `/db`/`get`/`mutate` surface. Motivating case (wholesale-command-station, 2026-08-13): `_log` grew to 4,164,727 rows and filled a 1GB production volume to 100%, and every recovery path zonai ships — `DELETE`, `VACUUM`, `wal_checkpoint` — needs a write the full disk is denying. A separate file changes what is possible rather than just what is tidy: `unlink` is the only reclamation primitive that does not require the resource being reclaimed, `VACUUM` takes its exclusive lock on the disposable data instead of on the application's own tables, and `PRAGMA max_page_count` becomes usable at all (it caps a *file*, so on a shared database the ceiling is hit by whichever write arrives first — application inserts included). The `_log` split is being done directly as a one-off; this entry is the generalization. Worth designing around the idea that some tables are *disposable* — high-churn, bounded-retention, reconstructible-or-not-worth-reconstructing — and that the schema is the right place to say so, since that one declaration is what would let retention, capping, vacuum policy and crash recovery all be derived rather than hand-wired per table. Candidates beyond `_log`: `_rate_limit`, `_auth_challenges`, `_cron_jobs`. Deliberately not scoped further here; flagged as a real need, not designed.
- [ ] Add a "view" table concept — a read-only, joined/projected shape defined once in schema, queryable through the normal `/db`/`get`/`mutate` surface like a real table. Motivating case (override_canvas, 2026-07-25): `ListBody`/`/db/list` has no column-projection support today — listing rows always returns every column, including large ones (e.g. a `recordings` table storing a full base64 payload inline) even when a UI only needs a handful of lightweight fields for a list view. A generic `fields:`/`select:` param on `ListBody` would fix that specific case, but a proper "view" — a named, reusable projection (and eventually a join across tables) defined in schema once — is the more durable fix: it'd also cover "denormalize this join for the dashboard" cases without every caller re-specifying the same field list, and gives `raindrop` a real join story to build toward (see "Add support for one to many relationships" above — a view is a natural place to expose the joined shape once relationships exist). Deliberately not scoped further here; flagged as a real, recurring need, not designed.

## Backlog

### Auth

- [ ] Add OAuth authentication (mixins)
- [ ] Add email change
- [ ] Add impersonate
