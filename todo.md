# TODO

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

## DB

- Create "zonai_schema" classes to represent authentication classes
  - This will _not_ already have a table, but will be used for the user to extend to add their own columns
  - The idea is to have this as a base class with a lot of the core functionality already built in

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
