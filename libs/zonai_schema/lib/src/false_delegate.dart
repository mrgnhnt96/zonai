import 'package:raindrop/raindrop.dart';
import 'package:raindrop_sqlite/raindrop_sqlite.dart';

class FalseDelegate extends RaindropDelegate {
  FalseDelegate() : super(dialect: const SQLiteDialect());

  @override
  Future<DatabaseResult> execute(String query, List<Object?> values) {
    throw UnimplementedError();
  }

  @override
  Future<void> onClose() {
    throw UnimplementedError();
  }

  @override
  Future<void> onOpen() {
    throw UnimplementedError();
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(TransactionDelegate delegate) transaction,
  ) {
    throw UnimplementedError();
  }

  @override
  Stream<DatabaseResult> streamQuery(String query, List<Object?> values) {
    throw UnimplementedError();
  }
}
