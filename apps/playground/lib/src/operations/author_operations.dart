import '../schemas/authors.dart';
import 'package:zonai_schema/zonai_schema.dart';

// sup
final class AuthorOperations extends TableOperations<AuthorTable, Author> {
  AuthorOperations() : super(authors);
}

AuthorOperations main() => AuthorOperations();
