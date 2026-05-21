import 'package:zonai_playground/src/schemas/authors.dart';
import 'package:zonai_schema/zonai_schema.dart';

AuthorRecordRules main() => AuthorRecordRules();

class AuthorRecordRules extends RecordRules<AuthorCollection, Author> {
  AuthorRecordRules() : super(authors);

  @override
  Future<bool> canView(Jwt? jwt, Author record) async => true;

  @override
  Future<bool> canUpdate(Jwt? jwt, Author record) async => true;

  @override
  Future<bool> canDelete(Jwt? jwt, Author record) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt, Author record) async => true;
}
