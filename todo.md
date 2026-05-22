# TODO

## 5.19.2026

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
- [ ] Export records as JSON
- [ ] Add rate limiting
  - [ ] Blacklist IPs (needs to be outside of code to be reactive)

## 4.15.2026

- [ ] Support compiling to different arch-types
- [ ] Compile for linux

## Cron

- [ ] Create cron
- [ ] Support user defined cron jobs
- [ ] Clear logs after a week (configurable)
- [ ] Clear rate limits after a week (configurable)

## CLI

### `init` command

- [ ] Create built-in email templates
- [ ] Set up initial admin schema
- [ ] Create zonai.yaml file, with default values
- [ ] Add to `.gitignore`
  - [ ] `*.stop`
  - [ ] `zonai.sqlite*`

### Other

- write script to compile the server
- write script to compile the web app
- set up cli to serve the compiled server
- serve the compiled web app from the server
- when deployed, the cli should not watch the filesystem for changes, not have the ability to recompile

## Raindrop

- [ ] Add feature to alert/fail on breaking changes
- Investigate how to handle base classes for schemas & extending them

## Backlog

### Auth

- [ ] Add OAuth authentication (mixins)
- [ ] Add email change
- [ ] Add impersonate
