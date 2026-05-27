import 'package:zonai_playground/src/schemas/authors.dart';
import 'package:zonai_schema/zonai_schema.dart';

AuthorTableRules main() => AuthorTableRules();

final class AuthorTableRules extends TableRules<AuthorTable, Author> {
  AuthorTableRules() : super(authors);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  Future<bool> canUpdate(Jwt? jwt) async => true;

  Future<bool> canDelete(Jwt? jwt) async => true;

  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
