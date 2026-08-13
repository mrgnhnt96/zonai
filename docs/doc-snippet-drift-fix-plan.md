# Paying off the doc-snippet drift backlog (#26)

**Status: done, both phases.** Every ` ```dart ` fence in `docs/`,
`apps/docs/content/**` and `ai_templates.dart` is now either analyzed or
tagged `no-analyze` with its reason in the prose beside it, and a test fails
if a new one is neither. There is no baseline and reintroducing one should be
treated as a regression.

This doc is the record of what changed and why.

## The check

`fe56393` added `apps/playground/test/doc_snippets_test.dart`. It pulls every
fenced ` ```dart ` example out of `docs/*.md`, `apps/docs/content/**/*.md` and
`apps/zonai/lib/src/commands/ai/ai_templates.dart`, keeps the self-contained
ones, and runs `dart analyze` over them.

```
cd apps/playground && dart test test/doc_snippets_test.dart
```

- Snippets are written under `apps/playground/lib/src/__doc_snippets__/`
  (deleted afterwards) because the examples use the relative imports of a real
  zonai project — `../ids.dart`, `../schemas/items.dart` — which only resolve
  from inside one.
- `package:my_app/...` is the docs' stand-in for the reader's own project. The
  test rewrites `src/schemas/X.dart` to the playground's table where one exists
  (`users`, `items`, `posts`, `authors`, `companies`) and to
  `apps/playground/test/fixtures/doc_snippets/X.dart` otherwise (`tasks`,
  `profiles`, `articles`), and rewrites `src/ids.dart` to the fixtures' own
  `ids.dart`.
- The test fails if any checked snippet stops compiling, and separately if one
  of the fixtures or scaffolds does. A snippet that is deliberately not
  compilable tags its fence ```dart no-analyze and explains itself in the
  prose; that is the only opt-out, and it should stay rare.

`docs/*.md`, `apps/docs/content/**` and `ai_templates.dart` all have verify
rules pointing at this test, so a commit touching them runs it.

### Traps

- **Editing `apps/docs/content/**` means regenerating the search index**:
  `sip run docs index`. If you added or renamed a heading you must also rebuild
  the site (`cd apps/docs && dart run jaspr_cli:jaspr build`) — one of
  `apps/docs`'s tests checks every index anchor against the built HTML, and a
  stale build fails it.
- **The AI templates are duplicated.** Most snippets appear twice in
  `ai_templates.dart`. Where the two copies are byte-identical they share one
  key; where they differ slightly they do not. Either way **both copies must be
  fixed** — grep before assuming you are done.

## What changed

Coverage went from 67 self-contained snippets to 70 — fixing the ID examples
turned two prose fragments into checkable files, and the `known-issues.md`
sketch dropped out of the set when it was tagged `no-analyze`.

**Typed IDs (`quick-start`, `schemas/defining-tables`, `schemas/auth-tables`).**
The docs told readers to write `class UsersId extends Id`, which has never
compiled: `zonai_schema`'s `Id` is an `abstract interface class`. The docs now
teach the shape `zonai dev` actually generates — a local `sealed class Id
implements z.Id` in `lib/src/ids.dart` holding `value`, with one thin subclass
per table — because that is what `init_scaffold.dart` writes, what
`schema_scaffold.dart` appends to, and what `create_schema.dart` greps for.
That decision was made from the CLI's own scaffolding rather than picked.

**Column types.** `CreatedAtColumn`, `UpdatedAtColumn`, `IntegerColumn` and
`BoolColumn` do not exist; the real names are `DateTimeColumn`,
`ColumnType<DateTime?>`, `IntColumn` and `BooleanColumn`. There is no
`isNullable:` argument either — a column is nullable when the accessor handed
to the builder returns a nullable type, and `$.updatedAt` is always nullable.
`defining-tables`' column table said otherwise and now says this.

**Extensions.** `CreateExtension`, `UpdateExtension` and `DeleteExtension` do
not exist. The create/update/delete hooks are plain overridable methods on
`Extension<R>`; `AuthExtension<R>` is the only mixin and takes one type
argument. Every hook takes a trailing `Jwt? jwt`. `email.send.*` takes the
recipient positionally plus `table:`. Fixed in `extensions/auth-hooks.md`,
`docs/extensions.md` and both AI-template copies, including the mixin tables
that listed the three imaginary mixins.

**Globals.** The AI templates' reference tables had `collection:` nearly
everywhere. Real: `get.one/many(tableName:, where:)`,
`mutate.create.one(tableName:, object:)`, `mutate.delete.many(tableName:,
where:)` — and `mutate.update.one(table:, updates:, where:)`, which really is
the odd one out.

**Auth rules** (`rules/auth-rules.md`) was rewritten rather than patched. It
described `canSignUp(SignUpData)` / `canSignIn(User)` on a `AuthTableRules`
*mixin*. In reality `AuthTableRules` is a base class you extend (an `AuthTable`
is not a `Table`, so `TableRules<UserTable, User>` will not even accept one),
its only auth method is `canAuthenticate(Jwt?, AuthType)`, and
`canSignUp`/`canSignIn`/`canPasswordReset` live on `AuthRowRules` taking
`(Jwt?, AuthType)`. `SignUpData` does not exist. None of the page's examples
were expressible against the real API, including every "Common Pattern".

**Photo rules** (`rules/photo-rules.md`) was also rewritten. It documented a
`PhotoRules` base class and a `Photo` row type, neither of which exists — but
the *capability* does: both internal photo rules classes are constructed with
`canBeOverridden: true`, and `db_rules.dart` honours that, so you replace them
with an ordinary `TableRules`/`RowRules` over `PhotosTable`/`PhotoEntry`. This
did not need the "build it or delete the page" decision the earlier draft of
this doc called for — the code already answered it.

**Two bugs found while verifying, beyond the compile errors.** `row-rules.md`
compared `jwt?.userId` (an `Id`) against `before.createdBy.value` (a `String`),
which is silently always false — an ownership check that would deny every
owner. And `docs/rules.md` still documented the photo API as `/photos` with a
`row.collection` field; the controller is `@Controller('img')` and the field is
`row.table`.

**Harness.** Errors in the copied fixtures used to be dropped on the floor
(`if (snippet == null) continue`). That is worse than invisible: a broken
fixture takes down every snippet importing it, and those snippets are
baselined at the time, so the suite stayed green while reporting real breakage
as already-excused drift. Fixture errors are now collected and asserted on before
the snippet checks. This was found by hitting it — a doc comment in the `tasks`
fixture referenced `[Id]`, ambiguous between the fixture's `ids.dart` and
`zonai_schema`, and the suite passed anyway.

## Phase 2 — the fragments (done)

Only 70 of 276 fences were self-contained. The rest are fragments — a bare
`@override` member, a few loose statements, an argument list — and compiling
one means knowing what it sits inside, which cannot be inferred. It is now
declared on the fence:

````
```dart in:extension-user
@override
Future<void> onSignUp(User user, Jwt? jwt) async { ... }
```
````

`in:<name>` resolves to `apps/playground/test/fixtures/doc_scaffolds/<name>.dart`,
a real Dart file with a `// <<body>>` marker where the fragment is spliced.
Each scaffold is also analyzed with an empty body, so a scaffold that rots
against the API fails as itself rather than as a pile of unexplained drift in
every doc spliced into it. See that directory's README for what belongs in one.

Three tests hold it together: every checkable snippet analyzes, every `in:` tag
names a scaffold that exists (a typo would otherwise skip a fragment in
silence), and no fence escapes unchecked.

### What tagging them found

The premise held. Roughly a third of the newly-checked fragments did not
compile, and the errors were not cosmetic:

- **`ZonaiStorage` is not in the client's public API.** `1ce1a59` split
  file-backed storage behind `package:zonai_client/storage.dart` and dropped
  the export while doing it, taking the browser-safe factories with it. Three
  pages taught it. Restored as an explicit `show`.
- **auth-operations documented three getters that are async methods**, so
  every override on that page conflicted with the real member.
- **Essentially every dart-client example**: `fromJson` missing everywhere,
  `updateOne`/`deleteOne` that do not exist, `CreateBody(data:)` for
  `object:`, `String` where an `EmailAddress` goes, `PhotoCreateMeta(column:)`.
- **`AuthExtension<UserTable, User>`** (it takes one argument) with an
  `onSignUp` missing its `Jwt? jwt`, in the AI templates and two pages.
- **`final DateTimeColumn? updatedAt;`** in the schema template every new
  project's users table is copied from — `$.updatedAt` is always nullable, so
  the file does not build.
- **`CronJob(name: ...)`** on the catch-up page: `CronJob` is an abstract base
  class and has never been constructible.
- The ownership bug again, in three fragments beside the checked example it
  had already been fixed in.

Fences that held two things which cannot coexist in one file — an old
signature next to its replacement, two classes with two `main`s, three
alternative policies — were split, because each half is worth checking.

### The one thing left visible rather than fixed

The custom-operation example (`operations/overview.md` and the AI templates) is
tagged `no-analyze` because it cannot be written against the public API at all:

- `Where.sql(...)` is in `src/types/where_sql.dart`, which `zonai_schema.dart`
  does not export.
- A bare `table` inside a `TableOperations` subclass resolves to the top-level
  `table()` function from `zonai_schema`, not the inherited getter. `this.table`
  works.
- `custom(...)` is declared to return `rd.ToQuery`, and an update with a
  `where` is an `UpdateWhereBuilder`, which is not one.

That is an API gap, not a typo, so it is left standing where someone can see
it rather than quietly rewritten into something that compiles.

## What this still does not do

It does not know whether an example is *correct*, only that it compiles. The
ownership check comparing an `Id` to a `String` compiled; so did the photo API
documented under the wrong route. Both were found by reading the fragments the
tagging forced open, not by the analyzer.
