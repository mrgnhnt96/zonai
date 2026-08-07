import 'package:zonai_schema/gen/raindrop/raindrop/raindrop.dart';
import 'package:zonai_schema/gen/raindrop/raindrop_sqlite/src/sqlite_dialect.dart';

class FalseDelegate extends RaindropDelegate {
  FalseDelegate() : super(dialect: const SQLiteDialect());

  @override
  Future<DatabaseResult> execute(String query, List<Object?> values) {
    throw UnimplementedError();
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TransactionDelegate delegate) transaction,
  ) {
    throw UnimplementedError();
  }
}
