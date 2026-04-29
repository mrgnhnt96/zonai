import 'package:zonai/src/deps/zonai_db.dart';

class DbHandler {
  const DbHandler();

  void get() {}

  Future<List<Map<String, Object?>>> search() async {
    final (error, result) = await zonaiDB.search('items', {});
    if (error != null || result == null) {
      throw StateError('Failed to search items: $error');
    }
    return result;
  }

  Future<List<Map<String, Object?>>> list() async {
    final (error, result) = await zonaiDB.list('items', {});
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
