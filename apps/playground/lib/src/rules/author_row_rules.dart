import 'package:zonai_playground/src/schemas/authors.dart';
import 'package:zonai_schema/zonai_schema.dart';

AuthorRowRules main() => AuthorRowRules();

class AuthorRowRules extends RowRules<AuthorTable, Author> {
  AuthorRowRules() : super(authors);

  @override
  Future<bool> canView(Jwt? jwt, Author row) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Author row) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Author row) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Author row) async => true;
}
