# TODO

## 5.19.2026

when running zonai serve, its important that we dont prompt or require input. We dont want to block a fresh deployment to a server

- [ ] When running with no config, make sure no exceptions are thrown
- [ ] When there are no admins, act as if the project hasn't been setup up and treat as a new project (provide docs)
- [ ] When serve is first run, if no .zonai dir exists, treat as new project (set up project)
- [ ] When serving the app, use nocterm to provide a good experience
- [ ] Create a command for `./zonai dev` that is interactive and `./zonai serve` that prints logs only
  - [ ] should prompt for new admin (text fields).  If class isn't created (can create admin class if one doesnt exist)
- [ ] Create GHA to compile the executable for different platforms (linux, macos, windows)
- [ ] Create a "request" for logger to save into db
    - this will help with tracking requests

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

### Dashboard

The dashboard will be the first page on website load. It should show a quick overview of the project and a snapshot of the database.

- [ ] Show requests per minute
- [ ] Show latest errors in 24 hours

### API

- [ ] Upload files (to local storage)
- [ ] Support `order_by` in queries
- [ ] Export records as JSON
- [ ] Add streamCount as new endpoint
- [ ] Blacklist IPs (needs to be outside of code to be reactive)
- [ ] Add last seen to jwt entry (?)
- [ ] Add refresh token endpoint (returns new JWT)
- [ ] add ability to set host and port in flags or .env

## Cron

- [ ] Create cron
  - Clean up logs
  - Clean up auth challenges
  - Clean up cron entries
  - Delete expired JWTs
  - Delete expired Photos signed urls
  - Delete old rate limits
- [ ] Support user defined cron jobs

## CLI

### `init` command

- [ ] Create built-in email templates
- [ ] Set up initial admin schema
- [ ] Create zonai.yaml file, with default values
- [ ] Add to `.gitignore`
  - [ ] `*.stop`
  - [ ] `zonai.sqlite*`

### `create` command

- [ ] Create schema (auto create all classes)

## 4.15.2026

- [ ] Support compiling to different arch-types
- [ ] Compile for linux

### Other

- when deployed, the cli should not watch the filesystem for changes, not have the ability to recompile
  - use the `--release` flag to determine this

## Raindrop

- [ ] Add feature to alert/fail on breaking changes
- Investigate how to handle base classes for schemas & extending them

## Backlog

### Auth

- [ ] Add OAuth authentication (mixins)
- [ ] Add email change
- [ ] Add impersonate
