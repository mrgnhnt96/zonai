import 'package:zonai_playground/src/schemas/authors.dart';
import 'package:zonai_schema/zonai_schema.dart';

AuthorCollectionRules main() => AuthorCollectionRules();

final class AuthorCollectionRules extends CollectionRules<AuthorCollection, Author> {
  AuthorCollectionRules() : super(authors);

  @override
  Future<bool> canView(Jwt? jwt) async => true;

  Future<bool> canUpdate(Jwt? jwt) async => true;

  Future<bool> canDelete(Jwt? jwt) async => true;

  Future<bool> canList(Jwt? jwt) async => true;

  @override
  Future<bool> canCreate(Jwt? jwt) async => true;
}
