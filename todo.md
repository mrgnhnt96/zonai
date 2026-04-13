# TODO

## CLI

- write script to compile the server
- write script to compile the web app
- set up cli to serve the compiled server
- serve the compiled web app from the server

- Instead of compiling each file for the extension and rules, we need to create a file that consumes the files and creates a single file that is then compiled.
  - Similar to how hooksman and build_runner work when compiling their hooks & builders

## DB

- Create "internal" classes to represent authentication classes
  - This will _not_ already have a table, but will be used for the user to extend to add their own columns
  - The idea is to have this as a base class with a lot of the core functionality already built in

### Mixins

- Create/update mixins (auto set)
- Super User
- Soft Delete
- Auth
  - Sets up user authentication

### Interaction

- The interaction with the DB needs to be completely dynamic, since we cannot generate the server code for the user's schemas. The schemas are not known at compile time.
- The schemas control how the database should be structured

## Raindrop

- Add support for multi-path schema definitions
- Investigate how to handle base classes for schemas & extending them

<!-- !! WARNING !! -->

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
