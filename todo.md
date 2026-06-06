# TODO

## 6.1.26

- [ ] When we have more credits, we need to verify the release process, everything passes except for windows atm
- [ ] When creating a new record that uses a foreign key, if the foreign key is an object, we should create the object first and then use the id to create the original record

### UI

- [ ] Add theme color support
- [ ] Pin collections (?)
- [ ] Add search history

### API

- [ ] Create references to photo from other collections when using the `photo` or `photos` column
- [ ] Add prefix & suffix positional optional params to Id.generate

## CLI

### `dev` command

The first run is determined whether there is a `zonai.yaml` file existing. If there isn't then we should prompt user if they would like to init

- [ ] Create built-in email templates
- [ ] Set up initial admin schema
- [ ] Create zonai.yaml file, with default values
- [ ] Add to `.gitignore`
  - [ ] `*.stop`
  - [ ] `zonai.sqlite*`
- [ ] Compile all workers if `zonai.yaml` does not exist (unless in release mode)
  - [ ] Create `zonai.yaml` with default values

#### Actions

- [ ] Create new admin (similar to how web works now, but without requiring authentication)
- [ ] Run cron jobs manually
- [ ] Send test emails
- [ ] Create new email templates
- [ ] start/stop server
- [ ] Trail server logs
- [ ] ping executables
- [ ] retrieve data from executables
  - [ ] rules (table + row)
- [ ] Create new schemas
  - [ ] Optionally run migrations post-create
- [ ] Run migrations
- [ ] Create new executable part (e.g. new rate limit for table)
- [ ] Clear database (delete file)
  - [ ] Have a confirmation step

## Raindrop

- [ ] Add feature to alert/fail on breaking changes
- Investigate how to handle base classes for schemas & extending them
- [ ] Add support for one to many relationships

## Backlog

### Auth

- [ ] Add OAuth authentication (mixins)
- [ ] Add email change
- [ ] Add impersonate
