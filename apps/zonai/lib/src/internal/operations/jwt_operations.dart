import 'package:zonai/src/internal/tables/jwt_table.dart';
import 'package:zonai_schema/src/operations/table_operations.dart';

final class JwtOperations
    extends TableOperations<JwtTable, JwtEntry> {
  JwtOperations() : super(jwts);
}

JwtOperations main() => JwtOperations();
