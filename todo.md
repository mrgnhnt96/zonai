# TODO

## 6.1.26

- [ ] When we have more credits, we need to verify the release process, everything passes except for windows atm
- [ ] When creating a new record that uses a foreign key, if the foreign key is an object, we should create the object first and then use the id to create the original record
- [x] ~~Fix the `get.*`/`addClaims` reentrant-IPC deadlock~~ Fixed in `5251cba` (`Mailman._send` split into a serialized write step and an unserialized await, so a reentrant nested send no longer queues behind its own outer request). See `docs/known-issues.md` #8's 2026-07-26 update for the real root cause (host-side `Mailman`, not worker-side `MessageHandler` as first suspected) and how it was verified. Confirmed downstream in override_canvas: `OrganizationRowRules`/`ClientAppRowRules`/`RecordingRowRules` now call `get.*` from inside `canView` for real, live collaborator-access checks, with the full integration suite (72 tests, `dart test --concurrency=2`) green and stable across repeated runs.
- [x] ~~`zonai serve` dies on its own after a short idle gap between requests~~ Reclassified 2026-07-26, likely not a zonai bug — see `docs/known-issues.md` #9's update. Couldn't reproduce as a real application defect (several minutes of idle/polling/real traffic against the actual compiled binary, no crash); the one death caught went straight into `Kill.force()`'s signal-driven shutdown sequence, not this entry's `_checkHealth`/health-check-exhausted symptom. override_canvas's own `todo.md`, same session, independently noted backgrounded `zonai serve` processes dying between separate shell-tool invocations for unrelated-to-zonai reasons — matches. Leaving the original write-up in known-issues.md as-is in case it still reproduces for someone in a real terminal session.

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
