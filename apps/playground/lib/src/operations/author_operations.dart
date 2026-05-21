import 'package:zonai_playground/src/schemas/authors.dart';
import 'package:zonai_schema/zonai_schema.dart';

final class AuthorOperations extends CollectionOperations<AuthorCollection, Author> {
  AuthorOperations() : super(authors);
}

AuthorOperations main() => AuthorOperations();
