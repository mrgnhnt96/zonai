import '../../../../../src/db_mutator/payloads/payloads.dart';
import '../../../../../src/deps/zonai_db.dart';

class DbHandler {
  const DbHandler();

  void get() {}

  Future<List<Map<String, Object?>>> list() async {
    final (error, result) = await zonaiDB.list(
      'items',
      .new(where: NotNull('id')),
    );
    if (error != null || result == null) {
      throw StateError('Failed to list items: $error');
    }
    return result;
  }

  void create() {}

  void update() {}

  void updateMany() {}

  void delete() {}
}
