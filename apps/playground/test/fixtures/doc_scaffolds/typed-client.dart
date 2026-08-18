// Statements that call the GENERATED typed client -- `client.posts.list(...)`,
// the column tokens, the write builders.
//
// This is the scaffold that could not exist until this campaign. Every fence on
// `/dart-client/typed-client` was `no-analyze` because the API it calls exists
// only after generation, and no scaffold carried a generated client. The
// playground commits one (`lib/gen/zonai/`, kept honest by
// `gen client --check`), so the snippets can now be analyzed against the real
// thing rather than trusted.
//
// The single import is deliberate and is itself under test: the generated
// barrel re-exports `zonai_client`, so `ZonaiClient`, `Eq`, `OrderByTerm`,
// `SortDirection`, `And` and `ListBody` all resolve through this one line. If
// that re-export regresses, every snippet spliced in here stops compiling.
//
// The bindings are getters rather than locals for the reason given in
// side-effects.dart: a fragment needs their type, not a value. They are only
// the ones the prose already establishes -- a `client`, the row or id an
// earlier example on the page produced.
//
// WHAT THIS STILL DOES NOT COVER, so nobody reads the page as fully checked.
// Ten of the page's 22 fences are spliced in here. The other twelve are
// `no-analyze` for four reasons, none of them "nobody got to it":
//
//  * Three illustrate something that is not a statement -- an `import` line,
//    the `export ... hide` directive the generator emits. There is no body to
//    splice.
//  * Six call tables the docs invent (`books`, `articles`, `notes`) because
//    the prose reads better with them than with `cell_edit_fixtures`. Covering
//    those needs a generated client for a fixture schema, committed and kept
//    honest by its own `--check` -- a second generated artifact in the repo.
//    That is a real piece of work and it belongs in its own change, not
//    bolted onto this one. The docs should not be rewritten to match the
//    playground's table names; the fixture should be built to match the docs.
//  * Two (`Where.isNull('published_at')`) name a column `posts` does not have.
//    Left alone for the same reason: bending the prose to fit the fixture is
//    how a doc stops reading like a doc.
//  * One is Flutter (`setState`), which this scaffold has no widget for.
import 'package:zonai_playground/gen/zonai/zonai_client.g.dart';

class TypedClientExample {
  ZonaiClient get client => throw UnimplementedError();

  /// The row a `get` earlier on the page returned.
  PostsRow get post => throw UnimplementedError();
  AuthorsRow get author => throw UnimplementedError();

  PostsId get postId => throw UnimplementedError();
  AuthorsId get authorId => throw UnimplementedError();

  /// The access token the auth pages establish.
  String get token => throw UnimplementedError();

  Future<void> run() async {
    // <<body>>
  }
}
