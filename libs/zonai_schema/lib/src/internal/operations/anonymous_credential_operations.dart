import 'package:zonai_schema/src/internal/tables/anonymous_credential_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class AnonymousCredentialOperations
    extends TableOperations<AnonymousCredentialTable, AnonymousCredential> {
  AnonymousCredentialOperations() : super(anonymousCredentials);
}

AnonymousCredentialOperations main() => AnonymousCredentialOperations();
