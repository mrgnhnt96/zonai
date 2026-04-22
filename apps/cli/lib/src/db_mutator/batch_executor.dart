import 'package:raindrop/raindrop.dart';

class BatchExecutor {
  BatchExecutor({required this.db});

  final Raindrop db;

  Future<void> execute(List<(String, List<Object?>)> queries) async {
    await db.transaction((tx) async {
      for (final (query, values) in queries) {
        await tx.execute(query, values);
      }
    });
  }
}
