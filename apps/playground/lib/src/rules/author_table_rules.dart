import 'package:zonai_playground/src/schemas/authors.dart';
import 'package:zonai_schema/zonai_schema.dart';

AuthorTableRules main() => AuthorTableRules();

/// The table layer only asks whether the caller may attempt the operation at
/// all; [AuthorRowRules] does the per-row ownership check, and a `canList`
/// that passes here still yields nothing to a caller who owns no rows.
final class AuthorTableRules extends TableRules<AuthorTable, Author> {
  AuthorTableRules() : super(authors);

  @override
  Future<bool> canView(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canList(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canCreate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canUpdate(Jwt? jwt) async => jwt != null;

  @override
  Future<bool> canDelete(Jwt? jwt) async => jwt != null;
}
