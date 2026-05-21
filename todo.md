# TODO

## 5.19.2026

### Auth

- [ ] Add OTP authentication
- [ ] Add OAuth authentication (mixins)
- [ ] Add magic link authentication (mixin)
- [ ] Add email verification
- [ ] Add password reset
- [ ] Add email change
- [ ] Add impersonate

### UI

- [ ] Add theme color support
- [ ] Create collection groups:
  - [ ] Pin collections (if any)
  - [ ] Normal collections
  - [ ] System collections
- [ ] Search collections
- [ ] Filter records
  - [ ] Add search history
- [ ] Sort by column
- [ ] Send test email

### API

- [ ] Upload files (to local storage)
- [ ] Support `order_by` in queries
- [ ] Support cron jobs
- [ ] Support enums
- [ ] Support expand columns
- [ ] Export records as JSON
- [ ] Add rate limiting
- [ ] Support multiple `AppConfig` with `flavor`s
- [ ] Detect `[.<flavor>].env` files and compile them into the `appConfig` executable

## 4.15.2026

- [ ] Support compiling to different arch-types
- [ ] Compile for linux
- [ ] create a \_logs table, forward all logs to it
  - [ ] Run ttl of 1 week
- [ ] - if not compiled, before every request, check for a “stop” file (which will be generated on recompile) and restart the process. (Or check the file timestamp, and restart based off of that)

## CLI

### `init` command

- [ ] Create built-in email templates
- [ ] Set up initial admin schema
- [ ] Create zonai.yaml file, with default values

### Other

- write script to compile the server
- write script to compile the web app
- set up cli to serve the compiled server
- serve the compiled web app from the server
- when deployed, the cli should not watch the filesystem for changes, not have the ability to recompile

### Message Handler

- Don't kill the process until after the compilation is complete (when a restart is needed)
  - The DB should auto start the rule/extension process if it is not available
- Check for `.stop` file and restart the process if it exists
  - Should pause all requests until the process is restarted
  - Should wait until all pending requests are completed

## Raindrop

- [ ] Add feature to alert/fail on breaking changes
- Investigate how to handle base classes for schemas & extending them
