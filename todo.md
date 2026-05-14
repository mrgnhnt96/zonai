# TODO

## 5.11.2026 — Inline TODOs (synced from code comments)

### zonai / zonai_schema

- [ ] `password_column.dart`: ensure passwords are hashed before persistence (see column TODO)
- [ ] `zonai_db.dart`: make auth `appPepper` configurable (currently hard-coded)
- [ ] `zonai_db.dart`: send auth record objects to the extension for sanitization (`_authRecord`, sign-up result path)
- [ ] `db_operations.dart`: resolve operations directory from settings (replace `__TODO__GET_OPERATIONS_DIR__`)
- [ ] Add optional single or multi authentication
  - [ ] Single would upsert and would replace any old JWT
  - [ ] Multi would insert and allow multiple JWTs (allowing multiple devices)

## 4.15.2026

- [ ] Support compiling to different arch-types
- [ ] Compile for linux
- [ ] create a \_logs table, forward all logs to it
  - [ ] Run ttl of 1 week
- [ ] - if not compiled, before every request, check for a “stop” file (which will be generated on recompile) and restart the process. (Or check the file timestamp, and restart based off of that)
- [ ] create a “scheduleOperation” that will be used to add queries to the transaction (from within an extension)
- [ ] Setup `zonai` to be used as a library within a server
  - [ ] This way I can use this within a server project, and not need to create a new server just for the DB

## CLI

- write script to compile the server
- write script to compile the web app
- set up cli to serve the compiled server
- serve the compiled web app from the server
- when deployed, the cli should not watch the filesystem for changes, not have the ability to recompile

### Message Handler

- Don't kill the process until after the compilation is complete
  - The DB should auto start the rule/extension process if it is not available

### Mixins

- Create/update mixins (auto set)
- Super User
- Soft Delete
- Auth
  - Sets up user authentication

### Emails

- Use raw html files for emails + mustache syntax for templating

## Raindrop

- [ ] Add feature to alert/fail on breaking changes
- Investigate how to handle base classes for schemas & extending them

### Backlog

- Add support for multi-path schema definitions
