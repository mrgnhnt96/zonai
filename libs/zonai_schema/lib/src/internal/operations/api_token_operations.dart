import 'package:zonai_schema/src/internal/tables/api_token_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class ApiTokenOperations
    extends TableOperations<ApiTokenTable, ApiTokenEntry> {
  ApiTokenOperations() : super(apiTokens);
}

ApiTokenOperations main() => ApiTokenOperations();
