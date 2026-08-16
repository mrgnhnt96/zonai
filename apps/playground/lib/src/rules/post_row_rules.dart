import 'package:zonai_playground/src/schemas/posts.dart';
import 'package:zonai_schema/zonai_schema.dart';

PostRowRules main() => PostRowRules();

/// Public read, author-or-admin write -- the shape most content tables want.
///
/// `Post.authorId` points at `authors.id`, and the playground keys an author
/// row by the acting user's id (see `AuthorRowRules.canView`), so the
/// ownership test is `authorId == jwt.userId`. `Id.==` compares by `value`
/// across concrete id types, which is what makes `AuthorsId == UnknownId`
/// meaningful here.
///
/// `canUpdate` tests `before`, never `after`: `after` is the caller's proposed
/// row, so trusting its `author_id` would let anyone hand themselves a post by
/// claiming to own it.
class PostRowRules extends RowRules<PostTable, Post> {
  PostRowRules() : super(posts);

  @override
  Future<bool> canView(Jwt? jwt, Post row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Post row) async => _isAuthor(jwt, row);

  @override
  Future<bool> canUpdate(Jwt? jwt, Post before, Post after) async =>
      _isAuthor(jwt, before);

  @override
  Future<bool> canDelete(Jwt? jwt, Post row) async => _isAuthor(jwt, row);

  bool _isAuthor(Jwt? jwt, Post row) {
    if (jwt == null) return false;
    if (jwt.admin.canEdit case true) return true;

    return row.authorId == jwt.userId;
  }
}
