# TODO

## 6.1.26

- [x] ~~When we have more credits, we need to verify the release process, everything passes except for windows atm~~ Verified end to end on 2026-08-11 with the v0.6.1 release. Windows passes: `Verify Release` run `31444744628` was 15/15 green including `zonai-windows-x64`, and `Release` run `31558446442` published v0.6.1 with all 11 assets. Along the way the release process turned out to be broken in three separate places by the `zonai_schema-v*`/`zonai_client-v*` package releases taking GitHub's "latest" slot — see `docs/build-fallback-next-steps.md`.
- [ ] `--check` on the native-library builders only tests that the library *exists*, not that it's current, so a resqlite pin bump or argon2 builder change silently ships a stale library. Not biting yet (the cache postdates both). See `docs/build-fallback-next-steps.md` for the three options weighed; recommendation is a `fresh_native_libs` dispatch input now, a real staleness stamp later. Note `native-libs.yml` artifacts expire ~2026-10-30, after which every compile silently falls back to source builds.
- [ ] Real deployments still get worker IPC rather than in-process ops/rules, because zonai can never be an application dependency. The merged-`package_config` route is proven to work (with a zonai-wins merge policy — app-wins fails on `SQLiteDelegate`) but unbuilt. See `docs/build-fallback-next-steps.md`.
- [ ] When creating a new record that uses a foreign key, if the foreign key is an object, we should create the object first and then use the id to create the original record
- [x] ~~Fix the `get.*`/`addClaims` reentrant-IPC deadlock~~ Fixed in `5251cba` (`Mailman._send` split into a serialized write step and an unserialized await, so a reentrant nested send no longer queues behind its own outer request). See `docs/known-issues.md` #8's 2026-07-26 update for the real root cause (host-side `Mailman`, not worker-side `MessageHandler` as first suspected) and how it was verified. Confirmed downstream in override_canvas: `OrganizationRowRules`/`ClientAppRowRules`/`RecordingRowRules` now call `get.*` from inside `canView` for real, live collaborator-access checks, with the full integration suite (72 tests, `dart test --concurrency=2`) green and stable across repeated runs.
- [x] ~~`zonai serve` dies on its own after a short idle gap between requests~~ Reclassified 2026-07-26, likely not a zonai bug — see `docs/known-issues.md` #9's update. Couldn't reproduce as a real application defect (several minutes of idle/polling/real traffic against the actual compiled binary, no crash); the one death caught went straight into `Kill.force()`'s signal-driven shutdown sequence, not this entry's `_checkHealth`/health-check-exhausted symptom. override_canvas's own `todo.md`, same session, independently noted backgrounded `zonai serve` processes dying between separate shell-tool invocations for unrelated-to-zonai reasons — matches. Leaving the original write-up in known-issues.md as-is in case it still reproduces for someone in a real terminal session.
- [x] ~~No CORS support~~ Fixed as of 2026-07-26 — confirmed via a real preflight (`OPTIONS /db`/`OPTIONS /db/list`) against the compiled `apps/server` binary returning proper `access-control-*` headers for a cross-origin caller, and override_canvas's `apps/website` (a genuinely separate origin from its server) signing in successfully through a real browser. See `docs/known-issues.md` #7's update.
- [ ] `POST /auth/reset-password` crashes with an uncaught `scoped_deps` error (`read(ScopedRef<_Logger>)`...) instead of the graceful warn-and-skip `docs/email.md` promises, whenever `AppConfig.email` isn't set. See `docs/known-issues.md` #10 — root cause narrowed to `courier.dart`'s missing-email-config branch calling `logger.warn(...)` from a context that never had the logger scope established, not fixed. Blocks override_canvas's new "forgot password" UI from actually working end to end in this dev environment (no SMTP configured).
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
- [ ] Add a "view" table concept — a read-only, joined/projected shape defined once in schema, queryable through the normal `/db`/`get`/`mutate` surface like a real table. Motivating case (override_canvas, 2026-07-25): `ListBody`/`/db/list` has no column-projection support today — listing rows always returns every column, including large ones (e.g. a `recordings` table storing a full base64 payload inline) even when a UI only needs a handful of lightweight fields for a list view. A generic `fields:`/`select:` param on `ListBody` would fix that specific case, but a proper "view" — a named, reusable projection (and eventually a join across tables) defined in schema once — is the more durable fix: it'd also cover "denormalize this join for the dashboard" cases without every caller re-specifying the same field list, and gives `raindrop` a real join story to build toward (see "Add support for one to many relationships" above — a view is a natural place to expose the joined shape once relationships exist). Deliberately not scoped further here; flagged as a real, recurring need, not designed.

## Backlog

### Auth

- [ ] Add OAuth authentication (mixins)
- [ ] Add email change
- [ ] Add impersonate
