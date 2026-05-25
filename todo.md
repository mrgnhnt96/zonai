# TODO

## Future

- [ ] When we have more credits, we need to verify the release process, everything passes except for windows atm

## 5.19.2026

when running zonai serve, its important that we dont prompt or require input. We dont want to block a fresh deployment to a server

- [ ] When there are no admins, act as if the project hasn't been setup up and treat as a new project (provide docs)
- [ ] When serve (`dev`)is first run, if no .zonai dir exists, treat as new project (set up project)
- [ ] When serving (`dev`) the app, use nocterm to provide a good experience
- [ ] Create a command for `./zonai dev` that is interactive and `./zonai serve` that prints logs only
  - [ ] should prompt for new admin (text fields). If class isn't created (can create admin class if one doesnt exist)

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
- [ ] Export records as JSON
- [ ] Blacklist IPs (needs to be outside of code to be reactive)
- [ ] Add last seen to jwt entry (?)

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

## Raindrop

- [ ] Add feature to alert/fail on breaking changes
- Investigate how to handle base classes for schemas & extending them

## Backlog

### Auth

- [ ] Add OAuth authentication (mixins)
- [ ] Add email change
- [ ] Add impersonate
