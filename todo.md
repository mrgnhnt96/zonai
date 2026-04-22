# TODO

## 4.15.2026

- [ ] Support compiling to different arch-types
- [ ] Compile for linux
- [ ] Create a class to run Revali or the valley executable depending on if we are using production.
- [ ] Create a class to manage interactions with SQLite

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

BEFORE WE START JUMPING INTO GENERATING CODE, LETS SEE HOW FAR WE CAN GET WITHOUT GENERATING CODE:

- How do we define table security?
  - actions:
    - list/search
    - view
    - create
    - update
    - delete
  - This needs to be type safe and testable
- How does the client communicate to the server/db?
- How does the user define custom SQL queries?
- How does the user extend the database?
- How can the server access the schemas if its precompiled/dynamic?
  - It can't, it would need to be generated

# Ideas

- What if we created a couple different types of "Collection" classes that the user can extend?
  - Types
    - Base Collection
      - Methods:
        - List
        - Search
        - View
        - Create
        - Update
      - Each method would supply an instance of the request object
        - Protected would contain the user, JWT, etc
        - Public would not contain any of this
    - `PublicCollection extends BaseCollection`
    - `ProtectedCollection extends BaseCollection`
  - The return type of each method would be set, so the user would need to comply with the return type
  - The user could optimize the request if they wanted to, or they could use the default implementation `super.method()`
