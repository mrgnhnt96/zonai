import 'package:zonai_playground/src/schemas/authors.dart';
import 'package:zonai_schema/zonai_schema.dart';

AuthorRowRules main() => AuthorRowRules();

/// An author row is keyed by the acting user's id, so every decision here is
/// the same one: does this row belong to the caller (or is the caller an
/// admin)?
///
/// `canUpdate` tests `before` rather than `after` for the usual reason --
/// `after` is the caller's proposal, and honouring its `id` would let anyone
/// claim any author row.
class AuthorRowRules extends RowRules<AuthorTable, Author> {
  AuthorRowRules() : super(authors);

  @override
  Future<bool> canView(Jwt? jwt, Author row) async => _isSelf(jwt, row);

  @override
  Future<bool> canCreate(Jwt? jwt, Author row) async => _isSelf(jwt, row);

  @override
  Future<bool> canUpdate(Jwt? jwt, Author before, Author after) async =>
      _isSelf(jwt, before);

  @override
  Future<bool> canDelete(Jwt? jwt, Author row) async => _isSelf(jwt, row);

  bool _isSelf(Jwt? jwt, Author row) {
    if (jwt == null) return false;
    if (jwt.admin.canEdit case true) return true;

    return row.id == jwt.userId;
  }
}
