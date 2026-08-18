// Statements on `/dart-client/typed-client` that call the tables the page
// INVENTS -- `books`, `articles`, `notes`, `users` -- rather than the
// playground's own.
//
// Those tables are in the prose because it reads better with a shelf of books
// than with `cell_edit_fixtures`, and the enum examples only teach anything
// because `BooksShelf.reading` is a name a reader recognises. So the fixture
// was built to match the docs rather than the docs rewritten to match a
// fixture. `doc_fixture_client_golden_test.dart` owns that fixture and keeps it
// honest: its schema is authored there, and the client under
// `lib/gen/doc_fixture/` is regenerated and byte-compared, exactly as
// the playground's own committed client is.
//
// ONE import, like the playground scaffold, and for the same reason: the
// generated barrel re-exports `zonai_client`, so `Field`, `NumField`,
// `ListField` and `MapField` all resolve through this line. A second import
// appearing here means that re-export regressed -- which is a finding, not a
// thing to work around.
//
// WHAT IS STILL `no-analyze` ON THIS PAGE, and why none of it is "nobody got
// to it":
//
//  * The expand migration fence (`// before` / `// after`). Its "before" line
//    is `expand: ['book_id', 'book_id.owner_id']`, the string form that
//    STOPPED type-checking -- showing it failing to compile is the entire
//    point of the fence. It is also a bare argument fragment, not a statement.
//  * The two lines that demonstrate what an enum column stops you doing
//    (`final String shelf = book.shelf;`, `book.shelf.toUpperCase()`). They are
//    compile errors on purpose. The snippet harness has exactly two modes,
//    `in:<scaffold>` and `no-analyze` (doc_snippets_test.dart:178-181) -- there
//    is no "expected to fail" mode, and inventing one for two lines would put
//    more machinery in the harness than the fences are worth. Marked
//    `no-analyze` with the reason on the fence.
//  * Three fences that are directives, not statements, and two naming a
//    `published_at` column `posts` does not have. Unchanged from before.
import 'package:zonai_playground/gen/doc_fixture/zonai_client.g.dart';

class TypedClientFixtureExample {
  ZonaiClient get client => throw UnimplementedError();

  /// The row a `get` earlier on the page returned.
  BooksRow get book => throw UnimplementedError();

  /// The id an earlier example on the page established.
  ArticlesId get id => throw UnimplementedError();

  UsersId get userId => throw UnimplementedError();

  Future<void> run() async {
    // <<body>>
  }
}
