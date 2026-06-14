# TODO

## 6.1.26

- [ ] When we have more credits, we need to verify the release process, everything passes except for windows atm
- [ ] When creating a new record that uses a foreign key, if the foreign key is an object, we should create the object first and then use the id to create the original record

### UI

- [ ] Add theme color support
- [ ] Pin collections (?)
- [ ] Add search history
- [ ] Support user defined favicon
- [ ] When clicking on an error in the dashboard, open the trace in the logs table
- [ ] Add icon for "filter" in the row details panel next to each field. Will auto apply "column=..." filter

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

## Backlog

### Auth

- [ ] Add OAuth authentication (mixins)
- [ ] Add email change
- [ ] Add impersonate
