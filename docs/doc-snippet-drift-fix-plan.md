# Paying off the doc-snippet drift backlog (#26)

**Status: done.** All 26 baselined examples were fixed and the baseline file is
gone — there is no excuse list any more, and reintroducing one should be treated
as a regression. The single example that is genuinely not meant to compile (a
deliberately-elided sketch in `known-issues.md`) opts out at the fence instead,
with ```dart no-analyze, which shows up in the diff of the doc that owns it.

This doc is kept as the record of what changed and why, plus the one phase that
is still open.

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
- The test fails if any self-contained snippet stops compiling, and separately
  if one of the fixtures does. A snippet that is deliberately not compilable
  tags its fence ```dart no-analyze and explains itself in the prose; that is
  the only opt-out, and it should stay rare.

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

## Still open

### Phase 2 — the ~200 unchecked fragments

Only 70 of 274 fences are checked. The rest are fragments: a bare `@override`
member, a few loose statements. Compiling them means knowing which class or
function body they belong in, which can't be inferred — so it needs an
authoring convention, and that's a maintainer call rather than something to
pick unilaterally. The usual shape is an info-string tag on the fence:

````
```dart in:TableRules<TaskTable, Task>
@override
Future<bool> canCreate(Jwt? jwt) async => jwt != null;
```
````

with `no-analyze` for the deliberately-partial ones. That half is already in
use and needs no code — the extractor skips any fence carrying an info string,
so `no-analyze` works today; only the `in:` form needs building. Tagging ~200
fences is the bulk of the work; the extractor change is small. Worth agreeing
the `in:` syntax before anyone starts.

This matters more than the fragment count suggests: several of the errors above
sat in prose fragments right next to a checked snippet, and the auth-rules page
was wrong in *every* fragment while its one self-contained example was the only
thing the check could see.

Two things the check will still never do, worth stating whenever it's cited as
coverage: it doesn't look at fragments, and it doesn't know whether an example
is *correct* — only that it compiles. Both bugs in the "found while verifying"
note above compiled fine.
